local M = {}
---@type table<integer, gents.Session>
local registry = {}
---@type table<integer, boolean>
local closing = {}
local next_id = 0
local focus_count = 0

---@return integer
local function next_focus()
  focus_count = focus_count + 1
  return focus_count
end

---@class gents.Session
---@field id integer
---@field tool gents.Tool
---@field label string
---@field title? string
---@field cmd string[]
---@field resume? string Requested CLI conversation selector; restoration is owned by the CLI.
---@field cwd string
---@field buf integer
---@field job? integer Assigned after the terminal job starts.
---@field state gents.SessionState
---@field exit_code? integer
---@field tab? integer
---@field last_float? boolean Whether the most recent gents placement was floating.
---@field last_focus integer Increases each time the session buffer is entered.

---@return gents.Session[]
function M.list()
  local sessions = vim.tbl_values(registry)
  table.sort(sessions, function(a, b)
    return a.id < b.id
  end)
  return sessions
end

---@param id integer
---@return gents.Session?
function M.get(id)
  return registry[id]
end

---@return gents.Session?
function M.current()
  local session = registry[vim.b.gents_session]
  if session and session.buf == vim.api.nvim_get_current_buf() then
    return session
  end
end

---@param tool gents.Tool
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
    assert(type(requested) == "string" and requested:find("%S"), "gents: label must not be empty")
    assert(not labels[requested], "gents: session label already exists: " .. requested)
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

---@param tool gents.Tool
---@return table<string, string>
local function environment(tool)
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
  return env
end

---@param session gents.Session
local function unregister(session)
  registry[session.id] = nil
  -- Removal can precede job exit, or happen before a job ever starts.
  if package.loaded["gents.rex_pane_title"] then
    require("gents.rex_pane_title").refresh()
  end
end

---@param session gents.Session
---@return gents.Session?
function M.close(session)
  if registry[session.id] ~= session then
    return
  end
  unregister(session)
  require("gents.terminal_status").detach(session, "close")
  require("gents.send").detach(session)
  local running = session.state ~= "exited" and session.job and session.job > 0
  if running then
    closing[session.id] = true
    vim.fn.jobstop(session.job)
  end
  require("gents.window").hide(session)
  if not running and vim.api.nvim_buf_is_valid(session.buf) then
    vim.api.nvim_buf_delete(session.buf, { force = true })
  end
  return session
end

---Track a session's terminal buffer. A replaced buffer no longer owns the session.
---@param session gents.Session
---@param buf integer
local function watch(session, buf)
  vim.bo[buf].bufhidden = "hide"
  vim.b[buf].gents_session = session.id
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    desc = "Remember when the session was last focused",
    callback = function()
      session.last_focus = next_focus()
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if session.buf ~= buf then
        return
      end
      closing[session.id] = nil
      if registry[session.id] ~= session then
        return
      end
      unregister(session)
      require("gents.terminal_status").detach(session, "buffer")
      require("gents.send").detach(session)
      if session.job and session.job > 0 and session.state ~= "exited" then
        vim.fn.jobstop(session.job)
      end
    end,
  })
end

---@type fun(session: gents.Session, cmd: string[])
local relaunch

---Start cmd in the current buffer, which must be the session's buffer.
---@param session gents.Session
---@param cmd string[]
---@param fallback? string[] Command to relaunch with if this one fails while starting.
---@return integer
local function spawn(session, cmd, fallback)
  local on_exit = require("gents.config").get().on_exit
  return vim.fn.jobstart(cmd, {
    term = true,
    cwd = session.cwd,
    clear_env = true,
    env = environment(session.tool),
    on_exit = function(_, code)
      if
        fallback
        and code ~= 0
        and session.state == "starting"
        and not closing[session.id]
        and registry[session.id] == session
      then
        -- A CLI with nothing to continue exits before any input; start fresh.
        require("gents.terminal_status").detach(session, "exit")
        vim.schedule(function()
          relaunch(session, fallback)
        end)
        return
      end
      require("gents.send").detach(session)
      session.state = "exited"
      session.exit_code = code
      require("gents.terminal_status").detach(session, "exit")
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
      require("gents.events").emit("GentsSessionExit", {
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
end

---Finish setting up a session's terminal after its job starts.
---@param session gents.Session
local function finish(session)
  assert(session.job and session.job > 0, "gents: could not start " .. session.tool.name)
  vim.bo[session.buf].buflisted = require("gents.config").get().buflisted
  require("gents.buffer_names").update(session)
  require("gents.keys").attach(session.buf)
  vim.bo[session.buf].filetype = "gents_terminal"
end

---Replace a session's finished terminal with cmd, keeping its windows.
---@param session gents.Session
---@param cmd string[]
relaunch = function(session, cmd)
  local old = session.buf
  if registry[session.id] ~= session or closing[session.id] then
    -- Closed while waiting; the finished job will not report again.
    closing[session.id] = nil
    if vim.api.nvim_buf_is_valid(old) then
      vim.api.nvim_buf_delete(old, { force = true })
    end
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  session.buf, session.cmd = buf, cmd
  watch(session, buf)
  local wins = vim.fn.win_findbuf(old)
  for _, win in ipairs(wins) do
    vim.api.nvim_win_set_buf(win, buf)
  end
  local focused = vim.api.nvim_get_current_buf() == buf
  -- The old job's streams are closed, so its buffer can go before the new one
  -- takes the session's buffer name.
  if vim.api.nvim_buf_is_valid(old) then
    vim.api.nvim_buf_delete(old, { force = true })
  end
  local ok, err = pcall(function()
    require("gents.events").attach(session)
    require("gents.window").attach(session)
    local function start()
      session.job = spawn(session, cmd)
    end
    if wins[1] and vim.api.nvim_win_is_valid(wins[1]) then
      vim.api.nvim_win_call(wins[1], start)
    else
      vim.api.nvim_buf_call(buf, start)
    end
    require("gents.send").restart(session)
    finish(session)
    if focused and vim.api.nvim_get_current_buf() == buf then
      vim.cmd.startinsert()
    end
  end)
  if not ok then
    M.close(session)
    vim.notify("gents.nvim: " .. tostring(err), vim.log.levels.ERROR)
  end
end

---@param tool gents.Tool
---@param opts? gents.NewOptions
---@param cwd? string Working directory captured before a deferred launch.
---@return gents.Session
function M.new(tool, opts, cwd)
  opts = opts or {}
  cwd = cwd or vim.fn.getcwd(0)
  local tools = require("gents.tools")
  local cmd, resumed_last = tools.command(tool, opts, cwd)
  ---@type string[]?
  local fallback
  if resumed_last then
    fallback = tools.command(tool, vim.tbl_extend("force", opts, { auto_resume = false }), cwd)
  end
  local label = label_for(tool, opts.label)
  -- Allocate in the destination so Neovim associates its window options there.
  local win = require("gents.window").open(nil, opts.layout)
  next_id = next_id + 1
  ---@type gents.Session
  local session = {
    id = next_id,
    tool = vim.deepcopy(tool),
    label = label,
    cmd = cmd,
    resume = opts.resume,
    cwd = cwd,
    buf = vim.api.nvim_create_buf(false, true),
    state = "starting",
    last_float = vim.api.nvim_win_get_config(win).relative ~= "",
    last_focus = next_focus(),
  }
  registry[session.id] = session
  watch(session, session.buf)

  local ok, err = pcall(function()
    require("gents.events").attach(session)
    require("gents.window").attach(session)
    vim.api.nvim_win_set_buf(win, session.buf)
    session.tab = vim.api.nvim_get_current_tabpage()
    session.job = spawn(session, cmd, fallback)
    require("gents.send").attach(session)
    finish(session)
    vim.cmd.startinsert()
    require("gents.events").emit("GentsSessionStart", { id = session.id })
    if
      registry[session.id] == session
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == session.buf
    then
      require("gents.events").emit("GentsSessionShow", { id = session.id, win = win })
    end
  end)
  if not ok then
    M.close(session)
    error(err, 0)
  end
  return session
end

return M
