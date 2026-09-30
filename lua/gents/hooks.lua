local M = {}

---@class gents.hooks.Input
---@field hook_event_name? string
---@field session_id? string
---@field agent_id? string
---@field identifier? string
---@field clear? boolean
---@field expected? string

---Decode synchronous SessionStart hooks or an explicit CLI plugin report.
---@param payload string
---@param explicit boolean
---@param statusline? boolean Claude's foreground status-line input.
---@return string? identifier
---@return string? expected
---@return boolean accepted
function M.decode(payload, explicit, statusline)
  ---@type gents.hooks.Input
  local input = vim.json.decode(payload)
  assert(type(input) == "table", "gents: expected a conversation report object")
  if explicit then
    assert(input.expected == nil or type(input.expected) == "string", "gents: invalid expected ID")
    if input.clear == true then
      return nil, input.expected, true
    end
    assert(type(input.identifier) == "string", "gents: expected an identifier string")
    return input.identifier, input.expected, true
  end
  if (not statusline and input.hook_event_name ~= "SessionStart") or input.agent_id ~= nil then
    return nil, nil, false
  end
  assert(type(input.session_id) == "string", "gents: expected a session_id string")
  return input.session_id, nil, true
end

return M
