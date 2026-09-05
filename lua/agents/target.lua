local M = {}

---@alias agents.Target integer|string|fun(session: agents.Session): boolean

---@param target? agents.Target
---@param callback fun(session: agents.Session): any
---@return any
function M.with(target, callback)
  local registry = require("agents.session")
  local candidates = registry.list()
  if type(target) == "number" or type(target) == "string" then
    for _, session in ipairs(candidates) do
      if session.id == target or session.label == target then
        return callback(session)
      end
    end
    error("agents.nvim: no session matches target " .. tostring(target), 2)
  elseif type(target) == "function" then
    candidates = vim.tbl_filter(target, candidates)
    if #candidates == 0 then
      error("agents.nvim: no session matches target filter", 2)
    end
  elseif target ~= nil then
    error("agents.nvim: target must be a session id, label, or filter", 2)
  end

  if #candidates == 0 then
    return
  end

  local current = registry.current()
  for _, session in ipairs(candidates) do
    if current and session.id == current.id then
      return callback(session)
    end
  end

  local tab = vim.api.nvim_get_current_tabpage()
  local visible = {}
  for _, session in ipairs(candidates) do
    if require("agents.window").visible(session, tab) then
      visible[#visible + 1] = session
    end
  end
  if #visible == 1 then
    return callback(visible[1])
  end
  if #candidates == 1 then
    return callback(candidates[1])
  end

  require("agents.picker").sessions(candidates, callback)
end

return M
