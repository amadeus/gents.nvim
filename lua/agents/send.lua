local M = {}

---@class agents.send.Item
---@field text? string Nil identifies a separate submit keystroke.
---@field submit? boolean Whether the pasted message requests submission.

---@class agents.send.Queue
---@field timer uv.uv_timer_t
---@field items agents.send.Item[]
---@field started integer
---@field changed integer
---@field tick integer

---@type table<integer, agents.send.Queue>
local queues = {}

---@param session agents.Session
function M.detach(session)
  local queue = queues[session.id]
  queues[session.id] = nil
  if queue and not queue.timer:is_closing() then
    queue.timer:stop()
    queue.timer:close()
  end
end

---@param session agents.Session
---@param queue agents.send.Queue
---@return boolean
local function live(session, queue)
  return queues[session.id] == queue
    and require("agents.session").get(session.id) == session
    and session.state ~= "exited"
    and vim.api.nvim_buf_is_valid(session.buf)
end

---@param session agents.Session
---@param queue agents.send.Queue
local function advance(session, queue)
  if not live(session, queue) then
    return
  end
  if session.state == "starting" then
    local now = vim.uv.hrtime()
    local tick = vim.api.nvim_buf_get_changedtick(session.buf)
    if tick ~= queue.tick then
      queue.tick = tick
      queue.changed = now
    end
    local lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
    while lines[#lines] == "" do
      table.remove(lines)
    end
    if
      (now - queue.started) / 1e6 < 5000 and (#lines <= 5 or (now - queue.changed) / 1e6 < 500)
    then
      return
    end
    session.state = "ready"
  end

  local item = table.remove(queue.items, 1)
  if not item then
    queue.timer:stop()
    return
  end
  if item.text then
    vim.api.nvim_buf_call(session.buf, function()
      vim.api.nvim_put(vim.split(item.text, "\n", { plain = true }), "c", false, true)
    end)
    require("agents.events").emit("AgentsSend", { id = session.id, submit = item.submit == true })
  else
    vim.api.nvim_chan_send(assert(session.job), "\r")
  end
end

---@param session agents.Session
---@param queue agents.send.Queue
local function start(session, queue)
  queue.timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      advance(session, queue)
    end)
  )
end

---@param session agents.Session
function M.attach(session)
  M.detach(session)
  local now = vim.uv.hrtime()
  ---@type agents.send.Queue
  local queue = {
    timer = assert(vim.uv.new_timer()),
    items = {},
    started = now,
    changed = now,
    tick = vim.api.nvim_buf_get_changedtick(session.buf),
  }
  queues[session.id] = queue
  start(session, queue)
end

---@param session agents.Session
---@param text string
---@param submit? boolean
function M.enqueue(session, text, submit)
  local queue = queues[session.id]
  assert(queue and live(session, queue), "agents: cannot send to an exited or closed session")
  text = text:gsub("\r\n", "\n")
  if text:sub(-1) ~= "\n" then
    text = text .. "\n"
  end
  queue.items[#queue.items + 1] = { text = text, submit = submit == true }
  if submit then
    queue.items[#queue.items + 1] = {}
  end
  if not queue.timer:is_active() then
    start(session, queue)
  end
end

---@param session agents.Session
---@param focus boolean
local function present(session, focus)
  local origin = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_get_current_tabpage()
  ---@type integer?
  local destination
  for _, win in ipairs(vim.fn.win_findbuf(session.buf)) do
    if vim.api.nvim_win_get_tabpage(win) == tab then
      destination = win
      break
    end
  end
  local opened = destination == nil
  destination = destination or require("agents.window").open(session.buf)
  session.tab = vim.api.nvim_win_get_tabpage(destination)
  if focus then
    vim.api.nvim_set_current_win(destination)
    vim.cmd.startinsert()
  elseif vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
  if opened then
    require("agents.events").emit("AgentsSessionShow", { id = session.id, win = destination })
  end
end

---@param parts agents.Part[]
---@param ctx agents.Context
---@param opts agents.SendOptions
---@return agents.Session?
local function deliver(parts, ctx, opts)
  if opts.target == nil and #require("agents.session").list() == 0 then
    vim.notify(
      "agents.nvim: no sessions available; start one with :Agents new",
      vim.log.levels.WARN
    )
    return
  end
  return require("agents.target").with(opts.target, function(session)
    if session.state == "exited" then
      vim.notify(
        "agents.nvim: cannot send to exited session " .. session.label,
        vim.log.levels.ERROR
      )
      return
    end
    present(session, opts.focus == true)
    local text = require("agents.render").text(parts, ctx, session.tool)
    M.enqueue(session, text, opts.submit == true)
    return session
  end)
end

---@param items? agents.Item[]
---@param opts? agents.SendOptions
---@param range? { line1: integer, line2: integer }
---@return agents.Session?
function M.run(items, opts, range)
  local ctx = require("agents.context").capture(range)
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd.normal({ args = { "\27" }, bang = true })
  end
  opts = vim.deepcopy(opts or {})
  if items == nil then
    require("agents.picker").context(ctx, function(parts)
      deliver(parts, ctx, opts)
    end)
    return
  end
  local parts = require("agents.render").resolve(items, ctx)
  if not parts then
    vim.notify("agents.nvim: requested context is not available here", vim.log.levels.WARN)
    return
  end
  return deliver(parts, ctx, opts)
end

return M
