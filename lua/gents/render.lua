local M = {}

---@param part gents.Item
local function validate_part(part)
  assert(type(part) == "table", "gents: a part must be a text, path, or code table")
  local count = (part.text ~= nil and 1 or 0)
    + (part.path ~= nil and 1 or 0)
    + (part.code ~= nil and 1 or 0)
  assert(count == 1, "gents: a part must have exactly one of text, path, or code")
  if part.text ~= nil then
    assert(type(part.text) == "string", "gents: part.text must be a string")
  elseif part.path ~= nil then
    assert(
      type(part.path) == "string" and part.path ~= "",
      "gents: part.path must be a non-empty string"
    )
    if part.range ~= nil then
      local range = part.range
      assert(type(range) == "table", "gents: part.range must be a range table")
      assert(
        range.kind == "char" or range.kind == "line" or range.kind == "block",
        "gents: range.kind must be char, line, or block"
      )
      for _, pos in ipairs({ range.start, range.finish }) do
        assert(
          type(pos) == "table"
            and type(pos[1]) == "number"
            and pos[1] >= 1
            and pos[1] % 1 == 0
            and type(pos[2]) == "number"
            and pos[2] >= 0
            and pos[2] % 1 == 0,
          "gents: range endpoints must contain a positive row and non-negative column"
        )
      end
      assert(range.start and range.finish, "gents: a range requires start and finish")
    end
  else
    assert(type(part.code) == "string", "gents: part.code must be a string")
    assert(part.ft == nil or type(part.ft) == "string", "gents: part.ft must be a string")
  end
end

---@param items gents.Item[]
local function validate_items(items)
  assert(type(items) == "table" and vim.islist(items), "gents: send items must be a list")
  for _, item in ipairs(items) do
    if type(item) == "string" then
      assert(require("gents.providers").get(item), "gents: unknown provider: " .. item)
    elseif type(item) ~= "function" then
      assert(
        type(item) == "table",
        "gents: an item must be a provider name, part, fallback, or function"
      )
      if item.any ~= nil then
        assert(
          item.text == nil and item.path == nil and item.code == nil,
          "gents: a fallback cannot also be a part"
        )
        validate_items(item.any)
      else
        validate_part(item)
      end
    end
  end
end

---@param parts gents.Item[]?
---@return gents.Part[]?
local function snapshot(parts)
  if parts == nil then
    return nil
  end
  assert(
    type(parts) == "table" and vim.islist(parts),
    "gents: a provider must return a list of parts or nil"
  )
  if #parts == 0 then
    return nil
  end
  for _, part in ipairs(parts) do
    validate_part(part)
  end
  ---@cast parts gents.Part[]
  return vim.deepcopy(parts)
end

---@param item gents.Item
---@param ctx gents.Context
---@return gents.Part[]?
local function resolve_item(item, ctx)
  if type(item) == "string" then
    return snapshot(assert(require("gents.providers").get(item)).render(ctx))
  elseif type(item) == "function" then
    return snapshot(item(ctx))
  elseif item.any ~= nil then
    for _, alternative in ipairs(item.any) do
      local parts = resolve_item(alternative, ctx)
      if parts then
        return parts
      end
    end
    return nil
  end
  return snapshot({ item })
end

---Resolve providers immediately; the returned parts own their data across pickers.
---@param items gents.Item[]
---@param ctx gents.Context
---@return gents.Part[]?
function M.resolve(items, ctx)
  -- Validate all names before running providers, including unused fallbacks.
  validate_items(items)
  ---@type gents.Part[]
  local result = {}
  for _, item in ipairs(items) do
    local parts = resolve_item(item, ctx)
    if not parts then
      return nil
    end
    vim.list_extend(result, parts)
  end
  return #result > 0 and result or nil
end

---@param path string
---@param range? gents.Range
---@return string
function M.location(path, range)
  if not range then
    return "@" .. path
  end
  local first, last =
    math.min(range.start[1], range.finish[1]), math.max(range.start[1], range.finish[1])
  return "@" .. path .. ":" .. first .. (last ~= first and ("-" .. last) or "")
end

---@param path string
---@param cwd string
---@return string
function M.path(path, cwd)
  local base = vim.fs.normalize(cwd, { expand_env = false })
  local normalized = vim.fs.normalize(path, { expand_env = false })
  if not normalized:match("^/") and not normalized:match("^%a:/") then
    normalized = vim.fs.normalize(base .. "/" .. normalized, { expand_env = false })
  end
  if normalized == base then
    return "."
  end
  local prefix = base:sub(-1) == "/" and base or (base .. "/")
  return normalized:sub(1, #prefix) == prefix and normalized:sub(#prefix + 1) or normalized
end

---@param code string
---@param ft? string
---@return string
local function code_block(code, ft)
  local width = 3
  for run in code:gmatch("`+") do
    width = math.max(width, #run + 1)
  end
  local fence = string.rep("`", width)
  local language = (ft or ""):gsub("[\r\n`]", "")
  local trailing = code:sub(-1) == "\n" and "" or "\n"
  return fence .. language .. "\n" .. code .. trailing .. fence
end

---@param parts gents.Part[]
---@param ctx gents.Context
---@param tool? gents.Tool
---@return string
function M.text(parts, ctx, tool)
  ---@type string[]
  local result = {}
  local location = tool and tool.location or M.location
  for _, part in ipairs(parts) do
    validate_part(part)
    if part.text ~= nil then
      result[#result + 1] = part.text
    elseif part.path ~= nil then
      result[#result + 1] = location(M.path(part.path, ctx.cwd), part.range)
    else
      result[#result + 1] = code_block(part.code, part.ft)
    end
  end
  return table.concat(result, "\n")
end

return M
