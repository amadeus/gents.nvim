local M = {}

---@param identifier string
local function validate(identifier)
  assert(
    type(identifier) == "string"
      and identifier:find("%S")
      and not identifier:find("%c")
      and identifier:sub(1, 1) ~= "-",
    "gents: conversation identifier must be nonblank without control characters or a leading '-'"
  )
end

---Called by integrations bound to this terminal's GENTS_SESSION value.
---@param id integer
---@param identifier? string nil clears the current conversation.
---@param expected? string Update only if this is still the confirmed identifier.
---@return boolean Updated a live session; false for stale reports.
function M.report(id, identifier, expected)
  local session = require("gents.session").get(id)
  if not session or session.state == "exited" then
    return false
  end
  if expected ~= nil and session.conversation ~= expected then
    return false
  end
  if identifier ~= nil then
    validate(identifier)
  end
  session.conversation = identifier
  return true
end

---@param opts? gents.CopyReferenceOptions
---@return string
function M.copy(opts)
  local session = require("gents.session").current()
  assert(session, "gents: copy_reference requires a Gents session buffer")
  local identifier = session.conversation
  assert(identifier, "gents: conversation ID has not been reported; configure a CLI integration")
  validate(identifier)
  local configured = require("gents.config").get().tools
  local tool = configured[session.tool.name]
  assert(tool, "gents: tool is no longer configured: " .. session.tool.name)
  -- Validate the adapter too, including the existence of file-based histories.
  require("gents.tools").command(tool, { resume = identifier }, session.cwd)
  local text = require("gents.references").format(tool.name, identifier, configured)
  local register = opts and opts.register or '"'
  assert(
    type(register) == "string" and register:match('^[a-z"+*]$'),
    'gents: register must be a lowercase named register, ", +, or *'
  )
  vim.fn.setreg(register, text, "v")
  if register == '"' then
    -- setreg() does not apply 'clipboard' to the unnamed register as a yank does.
    local clipboard = vim.split(vim.o.clipboard, ",", { plain = true })
    for _, option in ipairs({ { "unnamedplus", "+" }, { "unnamed", "*" } }) do
      if vim.list_contains(clipboard, option[1]) then
        vim.fn.setreg(option[2], text, "v")
      end
    end
  end
  return text
end

return M
