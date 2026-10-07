local M = {}

---@alias gents.EventName "GentsSessionStart"|"GentsSessionExit"|"GentsSessionShow"|"GentsSessionHide"|"GentsSessionTitle"|"GentsReady"|"GentsStatusChanged"|"GentsSend"

---@param name gents.EventName
---@param data gents.SessionEvent|gents.ReadyEvent|gents.SendEvent|gents.TitleEvent|gents.StatusChangedEvent
function M.emit(name, data)
  vim.api.nvim_exec_autocmds("User", { pattern = name, data = data, modeline = false })
end

---@param session gents.Session
---@return gents.AgentEvent
function M.context(session)
  local focused = vim.api.nvim_get_current_buf() == session.buf
  local win = focused and vim.api.nvim_get_current_win() or require("gents.window").find(session)
  return {
    id = session.id,
    label = session.label,
    title = session.title,
    tool = session.tool.name,
    buf = session.buf,
    win = win,
    visible = win ~= nil,
    focused = focused,
  }
end

---@param session gents.Session
function M.attach(session)
  require("gents.terminal_status").setup(require("gents.config").get().terminal_status)
  vim.api.nvim_create_autocmd("TermRequest", {
    buffer = session.buf,
    desc = "Receive conversation titles and native program status",
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
      require("gents.terminal_status").receive(session, data.sequence, data.terminator)
    end,
  })
end

return M
