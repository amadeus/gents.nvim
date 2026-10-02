local M = {}
local initialized = false
local terminal_focused = true
local reporting = false
---@type table<integer, boolean>
local reported = {}

---@param body string
local function send(body)
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send("\027]7501;" .. body .. "\027\\")
  end
end

---@param session gents.Session
local function report(session)
  if not reporting or not vim.api.nvim_ui_send then
    return
  end
  local body = "state=done:id=gents/" .. session.id .. ":app=gents"
  -- OSC 7501 rejects control characters and limits decoded titles to 192 bytes.
  local title = session.label:gsub("[%z\1-\31\127]", ""):gsub("\194[\128-\159]", "")
  if #title <= 192 then
    body = body .. ":title=" .. vim.base64.encode(title)
  end
  send(body .. ":msg=" .. vim.base64.encode("Session needs attention"))
  reported[session.id] = true
end

---@param session gents.Session
function M.clear(session)
  session.attention = false
  if reported[session.id] then
    send("state=clear:id=gents/" .. session.id)
    reported[session.id] = nil
  end
end

local function clear_focused()
  if terminal_focused then
    local session = require("gents.session").current()
    if session then
      M.clear(session)
    end
  end
end

local function clear_reports()
  if next(reported) ~= nil then
    send("state=clear:id=gents")
    reported = {}
  end
end

---@param enabled boolean
function M.setup(enabled)
  if not initialized then
    initialized = true
    local group = vim.api.nvim_create_augroup("gents_attention", { clear = true })
    vim.api.nvim_create_autocmd("FocusLost", {
      group = group,
      callback = function()
        terminal_focused = false
      end,
    })
    vim.api.nvim_create_autocmd("FocusGained", {
      group = group,
      callback = function()
        terminal_focused = true
        clear_focused()
      end,
    })
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      group = group,
      callback = clear_focused,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = clear_reports })
  end
  if reporting == enabled then
    return
  end
  clear_reports()
  reporting = enabled
  if reporting then
    for _, session in ipairs(require("gents.session").list()) do
      if session.attention then
        report(session)
      end
    end
  end
end

---@param session gents.Session
function M.ready(session)
  if
    session.state == "exited"
    or (terminal_focused and vim.api.nvim_get_current_buf() == session.buf)
  then
    M.clear(session)
    return
  end
  session.attention = true
  report(session)
end

return M
