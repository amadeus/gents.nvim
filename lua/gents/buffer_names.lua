local M = {}

---@param text string
---@return string
local function clean(text)
  return vim.trim((text:gsub("[/\\%c]", " "):gsub("%s+", " ")))
end

---@param session gents.Session
---@return string
local function name_for(session)
  local tool = clean(session.tool.name)
  local label = clean(session.label)
  local title = session.title and clean(session.title) or ""
  if label == "" then
    label = tool ~= "" and tool or "session"
  end
  local display = title ~= "" and (tool ~= "" and tool or label) .. " · " .. title or label
  return "gents://" .. session.id .. "/" .. display
end

---@param session gents.Session
function M.update(session)
  local buf = session.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local name = name_for(session)
  local old_name = vim.api.nvim_buf_get_name(buf)
  if name == old_name then
    return
  end

  ---@type table<integer, boolean>
  local existing = {}
  for _, other in ipairs(vim.api.nvim_list_bufs()) do
    existing[other] = true
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd.file({
      args = { name },
      mods = { keepalt = true, silent = true },
      magic = { file = false, bar = false },
    })
  end)

  -- :file keeps the old name as an unloaded buffer. Remove only the entry
  -- created by this rename, so an old term:// name cannot launch another CLI.
  for _, other in ipairs(vim.api.nvim_list_bufs()) do
    if
      not existing[other]
      and vim.api.nvim_buf_get_name(other) == old_name
      and not vim.api.nvim_buf_is_loaded(other)
      and not vim.bo[other].buflisted
    then
      vim.api.nvim_buf_delete(other, {})
    end
  end
end

return M
