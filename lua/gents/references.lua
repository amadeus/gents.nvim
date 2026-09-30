local M = {}
local delimiters = [[`"'()[]{}<>,;!?]]

---@class gents.references.Reference
---@field tool string
---@field identifier string

-- Dots, colons, slashes, and backslashes remain part of bare identifiers.
---@param char string
---@return boolean
local function delimiter(char)
  return char:find("%s") ~= nil or (char ~= "" and delimiters:find(char, 1, true) ~= nil)
end

---@param line string
---@param first integer First byte after the tool's colon.
---@return integer last Last byte belonging to the reference, including brackets.
---@return string identifier
---@return boolean closed
local function identifier_at(line, first)
  if line:sub(first, first) == "[" then
    local depth = 1
    for index = first + 1, #line do
      local char = line:sub(index, index)
      if char == "[" then
        depth = depth + 1
      elseif char == "]" then
        depth = depth - 1
        if depth == 0 then
          return index, line:sub(first + 1, index - 1), true
        end
      end
    end
    return #line, line:sub(first + 1), false
  end
  local last = first - 1
  while last < #line and not delimiter(line:sub(last + 1, last + 1)) do
    last = last + 1
  end
  return last, line:sub(first, last), true
end

---Select only a configured tool reference containing the zero-based byte column.
---@param line string
---@param column integer
---@param configured_tools table<string, gents.Tool>
---@return gents.references.Reference?
function M.parse(line, column, configured_tools)
  local names = require("gents.tools").names(configured_tools)
  -- Names are matched literally; longer names can include another name's colon.
  table.sort(names, function(a, b)
    return #a > #b or (#a == #b and a < b)
  end)
  local first = 1
  while first <= #line do
    local boundary = first == 1 or delimiter(line:sub(first - 1, first - 1))
    local uri = boundary and line:sub(first):match([[^%a[%w+.-]*://[^%s`"'<>]*]]) or nil
    ---@type string?
    local tool
    if boundary and not uri then
      for _, name in ipairs(names) do
        if name ~= "" and line:sub(first, first + #name) == name .. ":" then
          tool = name
          break
        end
      end
    end
    if uri then
      first = first + #uri
    elseif tool then
      local start = first + #tool + 1
      local last, identifier, closed = identifier_at(line, start)
      if column >= first - 1 and column <= last - 1 then
        assert(closed, "gents: invalid conversation reference: missing closing ']'")
        assert(identifier:find("%S"), "gents: invalid conversation reference: empty identifier")
        return { tool = tool, identifier = identifier }
      end
      first = last + 1
    else
      first = first + 1
    end
  end
end

---Format a reference that the cursor parser can read without losing bytes.
---@param tool string
---@param identifier string
---@param configured_tools table<string, gents.Tool>
---@return string
function M.format(tool, identifier, configured_tools)
  local bracketed = false
  for index = 1, #identifier do
    if delimiter(identifier:sub(index, index)) then
      bracketed = true
      break
    end
  end
  local text = tool .. ":" .. (bracketed and ("[" .. identifier .. "]") or identifier)
  local ok, parsed = pcall(M.parse, text, 0, configured_tools)
  assert(
    ok and parsed and parsed.tool == tool and parsed.identifier == identifier,
    "gents: conversation identifier cannot be represented as a reference"
  )
  return text
end

return M
