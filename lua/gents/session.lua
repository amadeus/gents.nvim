local M = {}
---@type table<integer, agents.Session>
local registry = {}
---@type table<integer, boolean>
local closing = {}
local next_id = 0

---@class agents.Session
---@field id integer
---@field tool agents.Tool
---@field label string
---@field title? string
---@field cmd string[]
---@field cwd string
---@field buf integer
---@field job? integer Assigned after the terminal job starts.
---@field state agents.SessionState
---@field exit_code? integer
---@field tab? integer

---@return agents.Session[]
function M.list()
  local sessions = vim.tbl_values(registry)
  table.sort(sessions, function(a, b)
    return a.id < b.id
  end)
  return sessions
end

---@param id integer
---@return agents.Session?
function M.get(id)
  return registry[id]
end

---@return agents.Session?
function M.current()
  local session = registry[vim.b.agents_session]
  if session and session.buf == vim.api.nvim_get_current_buf() then
    return session
  end
end

---@param tool agents.Tool
---@param requested? string
---@return string
local function label_for(tool, requested)
  ---@type table<string, boolean>
  local labels = {}
  local count = 0
  for _, session in pairs(registry) do
    labels[session.label] = true
    if session.tool.name == tool.name then
      count = count + 1
    end
  end
  if requested then
    assert(type(requested) == "string" and requested:find("%S"), "agents: label must not be empty")
    assert(not labels[requested], "agents: session label already exists: " .. requested)
    return requested
  end
  local ordinal = count + 1
  local label = ordinal == 1 and tool.name or tool.name .. " #" .. ordinal
  while labels[label] do
    ordinal = ordinal + 1
    label = tool.name .. " #" .. ordinal
  end
  return label
end

---@param tool agents.Tool
---@param id integer
---@return table<string, string>
local function environment(tool, id)
  -- jobstart serializes false instead of unsetting it, so supply a full environment.
  ---@type table<string, string>
  local env = vim.fn.environ()
  for _, name in ipairs({
    "NVIM",
    "NVIM_LISTEN_ADDRESS",
    "NVIM_LOG_FILE",
    "VIM",
    "VIMRUNTIME",
    "TERM",
    "COLORTERM",
    "COLUMNS",
    "LINES",
    "TERMCAP",
    "COLORFGBG",
  }) do
    env[name] = nil
  end
  if vim.o.termguicolors then
    env.COLORTERM = "truecolor"
  end
  for name, value in pairs(tool.env or {}) do
    env[name] = value ~= false and value or nil
  end
  env.AGENTS_SESSION = tostring(id)
  return env
end

---@param session agents.Session
---@return agents.Session?
function M.close(session)
  if registry[session.id] ~= session then
    return
  end
  registry[session.id] = nil
  require("agents.send").detach(session)
  local running = session.state ~= "exited" and session.job and session.job > 0
  if running then
    closing[session.id] = true
    vim.fn.jobstop(session.job)
  end
  require("agents.window").hide(session)
  if not running and vim.api.nvim_buf_is_valid(session.buf) then
    vim.api.nvim_buf_delete(session.buf, { force = true })
  end
  return session
end

---@param tool agents.Tool
---@param opts? agents.NewOptions
---@param cwd? string Working directory captured before a deferred launch.
---@return agents.Session
function M.new(tool, opts, cwd)
  opts = opts or {}
  assert(opts.cmd == nil or opts.args == nil, "agents: cmd and args are mutually exclusive")
  local cmd = vim.deepcopy(tool.cmd)
  local override = opts.cmd
  if override ~= nil then
    cmd = vim.deepcopy(override)
  end
  assert(
    type(cmd) == "table" and vim.islist(cmd) and #cmd > 0 and cmd[1] ~= "",
    "agents: cmd must be a non-empty list of strings starting with an executable"
  )
  for _, arg in ipairs(cmd) do
    assert(type(arg) == "string", "agents: cmd must be a list of strings")
  end
  if opts.args ~= nil then
    assert(vim.islist(opts.args), "agents: args must be a list of strings")
    for _, arg in ipairs(opts.args) do
      assert(type(arg) == "string", "agents: args must be a list of strings")
      cmd[#cmd + 1] = arg
    end
  end
  local label = label_for(tool, opts.label)
  cwd = cwd or vim.fn.getcwd(0)
  local config = require("agents.config").get()
  local on_exit = config.on_exit
  -- Allocate in the destination so Neovim associates its window options there.
  local win = require("agents.window").open(nil, opts.layout)
  next_id = next_id + 1
  ---@type agents.Session
  local session = {
    id = next_id,
    tool = vim.deepcopy(tool),
    label = label,
    cmd = cmd,
    cwd = cwd,
    buf = vim.api.nvim_create_buf(false, true),
    state = "starting",
  }
  vim.bo[session.buf].bufhidden = "hide"
  vim.b[session.buf].agents_session = session.id
  registry[session.id] = session

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = session.buf,
    once = true,
    callback = function()
      closing[session.id] = nil
      if registry[session.id] ~= session then
        return
      end
      registry[session.id] = nil
      require("agents.send").detach(session)
      if session.job and session.job > 0 and session.state ~= "exited" then
        vim.fn.jobstop(session.job)
      end
    end,
  })

  local ok, err = pcall(function()
    require("agents.events").attach(session)
    require("agents.window").attach(session)
    vim.api.nvim_win_set_buf(win, session.buf)
    session.tab = vim.api.nvim_get_current_tabpage()
    session.job = vim.fn.jobstart(cmd, {
      term = true,
      cwd = cwd,
      clear_env = true,
      env = environment(tool, session.id),
      on_exit = function(_, code)
        require("agents.send").detach(session)
        session.state = "exited"
        session.exit_code = code
        if closing[session.id] then
          closing[session.id] = nil
          -- Deleting a terminal with pending PTY writes can hang Neovim.
          -- The exit callback runs after the job's streams have closed.
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(session.buf) then
              vim.api.nvim_buf_delete(session.buf, { force = true })
            end
          end)
        end
        require("agents.events").emit("AgentsSessionExit", {
          id = session.id,
          exit_code = code,
        })
        if on_exit == "close" and code == 0 then
          vim.schedule(function()
            M.close(session)
          end)
        end
      end,
    })
    assert(session.job > 0, "agents: could not start " .. tool.name)
    require("agents.send").attach(session)
    vim.bo[session.buf].buflisted = config.buflisted
    require("agents.buffer_names").update(session)
    require("agents.keys").attach(session.buf)
    vim.bo[session.buf].filetype = "agents_terminal"
    vim.cmd.startinsert()
    require("agents.events").emit("AgentsSessionStart", { id = session.id })
    if
      registry[session.id] == session
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == session.buf
    then
      require("agents.events").emit("AgentsSessionShow", { id = session.id, win = win })
    end
  end)
  if not ok then
    M.close(session)
    error(err, 0)
  end
  return session
end

return M
