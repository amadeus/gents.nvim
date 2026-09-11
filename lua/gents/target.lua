local M = {}

---@alias gents.Target integer|string|fun(session: gents.Session): boolean

---@generic T
---@param target? gents.Target
---@param callback fun(session: gents.Session): T|nil
---@param on_place? fun(session: gents.Session, layout: gents.Layout)
---@param eligible? fun(session: gents.Session): boolean Restrict actionable sessions after matching the target.
---@return T|nil
function M.with(target, callback, on_place, eligible)
  local registry = require("gents.session")
  local candidates = registry.list()
  if type(target) == "number" or type(target) == "string" then
    for _, session in ipairs(candidates) do
      if session.id == target or session.label == target then
        if eligible and not eligible(session) then
          return
        end
        return callback(session)
      end
    end
    error("gents.nvim: no session matches target " .. tostring(target), 2)
  elseif type(target) == "function" then
    candidates = vim.tbl_filter(target, candidates)
    if #candidates == 0 then
      error("gents.nvim: no session matches target filter", 2)
    end
  elseif target ~= nil then
    error("gents.nvim: target must be a session id, label, or filter", 2)
  end

  if eligible then
    candidates = vim.tbl_filter(eligible, candidates)
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

  require("gents.picker").sessions(candidates, callback, on_place)
end

return M
