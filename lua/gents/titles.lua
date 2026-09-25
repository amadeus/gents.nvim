local M = {}

---@type table<string, boolean>
local omp_markers = { [">"] = true, ["!"] = true, [":"] = true }

---@param title string
---@return string?
function M.claude(title)
  for _, prefix in ipairs({ "✳ ", "◐ ", "◑ " }) do
    if vim.startswith(title, prefix) then
      title = title:sub(#prefix + 1)
      break
    end
  end
  if title ~= "Claude Code" then
    return title
  end
end

---@param title string
---@return string?
function M.codex(title)
  -- The thread title item falls back to a thread UUID before it has a name.
  local uuid =
    title:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
  if title ~= "Codex" and not uuid then
    return title
  end
end

---@param title string
---@return string?
function M.opencode(title)
  return title:match("^OC | (.+)$")
end

---@param title string
---@return string?
function M.omp(title)
  local label = title:match("^π: (.+)$")
  if label then
    return label
  end
  local marker, text = title:match("^π (%S+) (.+)$")
  -- Accept the full braille block (U+2800–U+28FF), independent of spinner frames.
  if marker and (omp_markers[marker] or marker:match("^\226[\160-\163][\128-\191]$")) then
    return text
  end
end

---@param title string
---@return string
local function clean(title)
  return vim.trim((title:gsub("%c", " ")))
end

---@param session gents.Session
---@param raw string
function M.update(session, raw)
  local parser = session.tool.title
  if
    parser == false
    or session.state == "exited"
    or require("gents.session").get(session.id) ~= session
  then
    return
  end
  ---@type string?
  local title = raw
  if parser then
    title = parser(clean(raw), session)
    assert(title == nil or type(title) == "string", "gents: tool.title must return a string or nil")
  end
  if title then
    title = clean(title)
    if title == "" or title == session.cwd or title == vim.fs.basename(session.cwd) then
      title = nil
    end
  end
  if title ~= session.title then
    session.title = title
    require("gents.buffer_names").update(session)
    require("gents.events").emit("GentsSessionTitle", { id = session.id, title = title })
  end
end

return M
