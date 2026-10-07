local M = {}

---@param value string
---@return boolean
function M.text_valid(value)
  local i = 1
  while i <= #value do
    local a, b = value:byte(i, i + 1)
    local size = 1
    if a < 32 or a == 127 then
      return false
    elseif a >= 128 then
      if a >= 194 and a <= 223 then
        size = 2
        if a == 194 and b and b < 160 then
          return false
        end
      elseif a >= 224 and a <= 239 then
        size = 3
        if not b or (a == 224 and b < 160) or (a == 237 and b >= 160) then
          return false
        end
      elseif a >= 240 and a <= 244 then
        size = 4
        if not b or (a == 240 and b < 144) or (a == 244 and b >= 144) then
          return false
        end
      else
        return false
      end
      for offset = 1, size - 1 do
        local byte = value:byte(i + offset)
        if not byte or byte < 128 or byte > 191 then
          return false
        end
      end
    end
    i = i + size
  end
  return true
end

---@param value string
---@return boolean
local function id_valid(value)
  if #value > 128 or value == "" or value:find("[^A-Za-z0-9_.+/%-]") then
    return false
  end
  local count = 0
  for segment in (value .. "/"):gmatch("(.-)/") do
    count = count + 1
    if #segment < 1 or #segment > 32 or count > 8 then
      return false
    end
  end
  return true
end

---@param value string
---@param limit integer
---@return string?
local function decode(value, limit)
  local bare, padding = value:match("^([A-Za-z0-9+/]*)(=*)$")
  if not bare or #padding > 2 or #bare % 4 == 1 then
    return
  end
  if #padding > 0 and (#value % 4 ~= 0 or #padding ~= (4 - #bare % 4) % 4) then
    return
  end
  local ok, decoded = pcall(vim.base64.decode, bare .. string.rep("=", (4 - #bare % 4) % 4))
  if ok and #decoded <= limit and M.text_valid(decoded) then
    return decoded
  end
end

---@class gents.ProgramReport
---@field id string Empty string addresses the embedded terminal's root.
---@field state gents.ProgramState|"clear"
---@field msg? string
---@field title? string
---@field app? string
---@field kind? gents.ProgramKind
---@field progress? integer

---@param sequence string TermRequest sequence, without its terminator.
---@param terminator? string BEL or ST; defaults to ST.
---@return gents.ProgramReport?
function M.parse(sequence, terminator)
  if #sequence + #(terminator or "\027\\") > 4096 then
    return
  end
  ---@type string?
  local body = sequence:match("^\027%]7501;(.*)$")
  if not body then
    return
  end
  ---@type table<string, string>
  local fields = {}
  for pair in body:gmatch("[^:]+") do
    ---@type string?, string?
    local key, value = pair:match("^%s*([a-z]+)%s*=%s*(.-)%s*$")
    if key and value then
      if #key > 16 then
        return
      end
      if key == "id" and not id_valid(value) then
        return
      elseif key == "app" and #value > 32 then
        return
      elseif key == "msg" and #value > 2732 or key == "title" and #value > 256 then
        return
      end
      if not value:find("[^A-Za-z0-9_.,+/=%-]") then
        if key == "msg" or key == "title" then
          local decoded = decode(value, key == "msg" and 2048 or 192)
          if not decoded then
            return
          end
          fields[key] = decoded
        else
          fields[key] = value
        end
      end
    end
  end
  local state = fields.state
  if
    state ~= "idle"
    and state ~= "working"
    and state ~= "blocked"
    and state ~= "done"
    and state ~= "error"
    and state ~= "clear"
  then
    return
  end
  ---@type gents.ProgramReport
  local report = { id = fields.id or "", state = state, msg = fields.msg, title = fields.title }
  if fields.app and fields.app:match("^[A-Za-z0-9_.+%-]+$") then
    report.app = fields.app
  end
  if state == "blocked" then
    local kind = fields.kind
    if kind == "permission" or kind == "question" or kind == "auth" then
      report.kind = kind
    end
  end
  if state == "working" or state == "blocked" then
    local progress = fields.progress
    if progress and progress:match("^%d+$") then
      local number = tonumber(progress)
      if number and number <= 100 then
        report.progress = math.floor(number)
      end
    end
  end
  return report
end

---@param id string
---@param record gents.ProgramStatus
---@param app? string Effective inherited app.
---@param title? string Root label fallback.
---@return string
function M.serialize(id, record, app, title)
  local parts = { "state=" .. record.state, "id=" .. id }
  if app then
    parts[#parts + 1] = "app=" .. app
  end
  if record.kind then
    parts[#parts + 1] = "kind=" .. record.kind
  end
  if record.progress then
    parts[#parts + 1] = "progress=" .. record.progress
  end
  if record.title ~= nil or title ~= nil then
    parts[#parts + 1] = "title=" .. vim.base64.encode(record.title or title or "")
  end
  if record.msg ~= nil then
    parts[#parts + 1] = "msg=" .. vim.base64.encode(record.msg)
  end
  return table.concat(parts, ":")
end

return M
