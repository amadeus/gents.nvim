local M = {}

---@param sequence string
---@return boolean
local function is_notification(sequence)
  ---@type string?, string?
  local code, payload = sequence:match("^\027%](%d+);(.*)$")
  if not payload then
    return false
  end
  if code == "9" then
    -- OSC 9;4 reports progress rather than a completed turn.
    return payload ~= "4" and payload:sub(1, 2) ~= "4;"
  elseif code == "777" then
    return payload:sub(1, 7) == "notify;"
  elseif code ~= "99" then
    return false
  end
  ---@type string?
  local metadata = payload:match("^([^;]*);")
  if not metadata then
    return false
  end
  local complete, kind = true, "title"
  for entry in metadata:gmatch("[^:]+") do
    if entry:sub(1, 2) == "d=" then
      complete = entry == "d=1"
    elseif entry:sub(1, 2) == "p=" then
      kind = entry:sub(3)
    end
  end
  return complete and (kind == "title" or kind == "body")
end

---@alias gents.EventName "GentsSessionStart"|"GentsSessionExit"|"GentsSessionShow"|"GentsSessionHide"|"GentsSessionTitle"|"GentsReady"|"GentsSend"

---@param name gents.EventName
---@param data gents.SessionEvent|gents.ReadyEvent|gents.SendEvent|gents.TitleEvent
function M.emit(name, data)
  vim.api.nvim_exec_autocmds("User", { pattern = name, data = data, modeline = false })
end

---@param session gents.Session
---@param source "osc"|"hook"
---@return gents.ReadyEvent
function M.ready(session, source)
  local focused = vim.api.nvim_get_current_buf() == session.buf
  local win = focused and vim.api.nvim_get_current_win() or require("gents.window").find(session)
  ---@type gents.ReadyEvent
  local data = {
    id = session.id,
    label = session.label,
    tool = session.tool.name,
    buf = session.buf,
    win = win,
    visible = win ~= nil,
    focused = focused,
    source = source,
  }
  M.emit("GentsReady", data)
  return data
end

---@param session gents.Session
function M.attach(session)
  vim.api.nvim_create_autocmd("TermRequest", {
    buffer = session.buf,
    desc = "Receive session titles and ready notifications",
    callback = function(ev)
      ---@type vim.event.termrequest.data
      local data = ev.data
      -- b:term_title may already contain a later title from the same PTY read.
      -- Use each OSC payload so renames and resets are observed in order.
      -- Neovim does not report empty titles; tool placeholders signal resets.
      local title = data.sequence:match("^\027%][02];(.+)$")
      if title then
        require("gents.titles").update(session, title)
        return
      end
      if not is_notification(data.sequence) then
        return
      end
      if require("gents.session").get(session.id) == session then
        M.ready(session, "osc")
      end
    end,
  })
end

return M
