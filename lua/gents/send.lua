local M = {}

---@class gents.send.Item
---@field text? string Nil identifies a separate submit keystroke.
---@field submit? boolean Whether the pasted message requests submission.

---@class gents.send.Queue
---@field timer uv.uv_timer_t
---@field items gents.send.Item[]
---@field started integer
---@field changed integer
---@field tick integer

---@type table<integer, gents.send.Queue>
local queues = {}

---@param session gents.Session
function M.detach(session)
  local queue = queues[session.id]
  queues[session.id] = nil
  if queue and not queue.timer:is_closing() then
    queue.timer:stop()
    queue.timer:close()
  end
end

---@param session gents.Session
---@param queue gents.send.Queue
---@return boolean
local function live(session, queue)
  return queues[session.id] == queue
    and require("gents.session").get(session.id) == session
    and session.state ~= "exited"
    and vim.api.nvim_buf_is_valid(session.buf)
end

---@param session gents.Session
---@param queue gents.send.Queue
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
    require("gents.events").emit("GentsSend", { id = session.id, submit = item.submit == true })
  else
    vim.api.nvim_chan_send(assert(session.job), "\r")
  end
end

---@param session gents.Session
---@param queue gents.send.Queue
local function start(session, queue)
  queue.timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      advance(session, queue)
    end)
  )
end

---@param session gents.Session
function M.attach(session)
  M.detach(session)
  local now = vim.uv.hrtime()
  ---@type gents.send.Queue
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

---@param session gents.Session
---@param text string
---@param submit? boolean
function M.enqueue(session, text, submit)
  local queue = queues[session.id]
  assert(queue and live(session, queue), "gents: cannot send to an exited or closed session")
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

---@param parts gents.Part[]
---@param ctx gents.Context
---@param opts gents.SendOptions
---@return gents.Session?
local function deliver(parts, ctx, opts)
  if opts.target == nil and #require("gents.session").list() == 0 then
    local origin = require("gents.picker").origin()
    require("gents.picker").tools(function(tool, launch_opts)
      local text = require("gents.render").text(parts, ctx, tool)
      local session = require("gents.session").new(tool, launch_opts, ctx.cwd)
      if opts.focus == false then
        vim.cmd.stopinsert()
        if vim.api.nvim_win_is_valid(origin) then
          vim.api.nvim_set_current_win(origin)
        end
      end
      M.enqueue(session, text, opts.submit == true)
    end)
    return
  end
  ---@param session gents.Session
  ---@param layout? gents.Layout
  ---@return gents.Session?
  local function send(session, layout)
    if session.state == "exited" then
      vim.notify(
        "gents.nvim: cannot send to exited session " .. session.label,
        vim.log.levels.ERROR
      )
      return
    end
    require("gents.window").present(session, layout, opts.focus ~= false)
    local text = require("gents.render").text(parts, ctx, session.tool)
    M.enqueue(session, text, opts.submit == true)
    return session
  end
  return require("gents.target").with(opts.target, send, send)
end

---@param buf integer
---@return boolean
local function can_send_from(buf)
  for _, session in ipairs(require("gents.session").list()) do
    if session.buf == buf then
      vim.notify("gents.nvim: send context from a non-session buffer", vim.log.levels.WARN)
      return false
    end
  end
  return true
end

---@param ctx gents.Context
---@param items? gents.Item[]
---@param opts? gents.SendOptions
---@return gents.Session?
function M.from_context(ctx, items, opts)
  if not can_send_from(ctx.buf) then
    return
  end
  opts = vim.deepcopy(opts or {})
  if items == nil then
    require("gents.picker").context(ctx, function(parts)
      deliver(parts, ctx, opts)
    end)
    return
  end
  local parts = require("gents.render").resolve(items, ctx)
  if not parts then
    vim.notify("gents.nvim: requested context is not available here", vim.log.levels.WARN)
    return
  end
  return deliver(parts, ctx, opts)
end

---@param items? gents.Item[]
---@param opts? gents.SendOptions
---@param range? { line1: integer, line2: integer }
---@return gents.Session?
function M.run(items, opts, range)
  if not can_send_from(vim.api.nvim_get_current_buf()) then
    return
  end
  local ctx = require("gents.context").capture(range)
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" or mode == "s" or mode == "S" or mode == "\19" then
    vim.cmd.normal({ args = { "\27" }, bang = true })
  end
  return M.from_context(ctx, items, opts)
end

return M
