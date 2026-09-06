local M = {}

---@alias agents.Target integer|string|fun(session: agents.Session): boolean

---@generic T
---@param target? agents.Target
---@param callback fun(session: agents.Session): T|nil
---@return T|nil
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

  if #candidates == 1 then
    return callback(candidates[1])
  end

  require("agents.picker").sessions(candidates, callback)
end

return M
