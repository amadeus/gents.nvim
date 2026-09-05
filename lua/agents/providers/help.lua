---@param line string
---@param reference boolean
---@param column? integer One-based byte column, including the tag delimiters.
---@return string?
local function tag(line, reference, column)
  local pattern = reference and "|([^%s|]+)|" or "%*([^%s%*]+)%*"
  local offset = 1
  while offset <= #line do
    local first, last, name = line:find(pattern, offset)
    if not first then
      return nil
    end
    local valid = reference and line:sub(first - 1, first - 1) ~= "\\"
      or not reference and (last == #line or line:sub(last + 1, last + 1):match("%s"))
    if valid and (not column or (first <= column and column <= last)) then
      return name
    end
    offset = last + 1
  end
end

---@param line string
---@return boolean
local function divider(line)
  return line:match("^===+%s*$") ~= nil or line:match("^---+%s*$") ~= nil
end

---@param ctx agents.Context
---@return agents.Part[]?
return function(ctx)
  if vim.bo[ctx.buf].filetype ~= "help" then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)
  local row = math.min(ctx.cursor[1], #lines)
  local selected = tag(lines[row], false, ctx.cursor[2] + 1)
    or tag(lines[row], true, ctx.cursor[2] + 1)
  local first, last = 1, #lines
  ---@type string?
  local section_tag
  local example = false
  for i, line in ipairs(lines) do
    -- Help examples end at '<' or any other non-indented line.
    if line:find("^[^ \t]") then
      example = false
    end
    if not example then
      local definition = tag(line, false)
      -- Keep adjacent tagged table rows together as part of their heading.
      local heading = definition
        and (i == 1 or lines[i - 1]:match("^%s*$") or divider(lines[i - 1]))
      if divider(line) or heading then
        if i > row then
          last = i - 1
          break
        end
        first, section_tag = i, definition
      end
      example = line:match("^>[a-z0-9]*$") ~= nil or line:match(" >[a-z0-9]*$") ~= nil
    end
  end
  while first <= last and lines[first]:match("^%s*$") do
    first = first + 1
  end
  while last >= first and lines[last]:match("^%s*$") do
    last = last - 1
  end
  if first > last then
    return nil
  end
  ---@type agents.Part[]
  local parts = {}
  selected = selected or section_tag
  if selected then
    parts[#parts + 1] = { text = "Help: :help " .. selected }
  end
  parts[#parts + 1] = { code = table.concat(lines, "\n", first, last), ft = "help" }
  return parts
end
