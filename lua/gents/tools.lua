local M = {}

-- Title parsers live in gents.titles, which loads with the first reported title
-- rather than at startup.
---@type gents.TitleParser
local function claude_title(title)
  return require("gents.titles").claude(title)
end

---@type gents.TitleParser
local function codex_title(title, session)
  return require("gents.titles").codex(title, session)
end

---@type gents.TitleParser
local function opencode_title(title)
  return require("gents.titles").opencode(title)
end

---@type gents.TitleParser
local function omp_title(title)
  return require("gents.titles").omp(title)
end

---@param path string
---@param range? gents.Range
---@return string
local function claude_location(path, range)
  if not range then
    return "@" .. path
  end
  local first, last =
    math.min(range.start[1], range.finish[1]), math.max(range.start[1], range.finish[1])
  return "@" .. path .. "#L" .. first .. (last ~= first and ("-" .. last) or "")
end

-- Characters consumed by the tools' @path parsers and unescapePath helpers.
local special_path_chars = " \t()[]{};|*?$`'\"#&<>!~,"

---@param path string
---@param escape_backslash boolean
---@return string
local function escape_path(path, escape_backslash)
  return (
    path:gsub(".", function(char)
      if special_path_chars:find(char, 1, true) or (escape_backslash and char == "\\") then
        return "\\" .. char
      end
      return char
    end)
  )
end

---@param path string
---@param range? gents.Range
---@return string
local function gemini_location(path, range)
  return require("gents.render").location(escape_path(path, true), range)
end

---@param path string
---@param range? gents.Range
---@return string
local function qwen_location(path, range)
  return require("gents.render").location(escape_path(path, false), range)
end

---@type gents.Tool[]
local builtins = {
  {
    name = "claude",
    cmd = { "claude" },
    title = claude_title,
    location = claude_location,
    url = "https://code.claude.com/docs/en/quickstart",
  },
  {
    name = "codex",
    cmd = { "codex", "-c", 'tui.terminal_title=["thread"]' },
    title = codex_title,
    url = "https://developers.openai.com/codex/cli",
  },
  {
    name = "opencode",
    cmd = { "opencode" },
    title = opencode_title,
    url = "https://opencode.ai/docs/",
  },
  {
    name = "opencode2",
    cmd = { "opencode2" },
    title = opencode_title,
    url = "https://opencode.ai/v2/docs",
  },
  {
    name = "amp",
    cmd = { "amp" },
    url = "https://ampcode.com/docs/cli",
  },
  {
    name = "aider",
    cmd = { "aider" },
    url = "https://aider.chat/docs/install.html",
  },
  {
    name = "copilot",
    cmd = { "copilot", "--banner" },
    url = "https://github.com/github/copilot-cli",
  },
  {
    name = "crush",
    cmd = { "crush" },
    url = "https://github.com/charmbracelet/crush",
  },
  {
    name = "cursor-agent",
    cmd = { "cursor-agent" },
    url = "https://cursor.com/docs/cli/installation",
  },
  {
    name = "gemini",
    cmd = { "gemini" },
    location = gemini_location,
    url = "https://github.com/google-gemini/gemini-cli",
  },
  {
    name = "grok",
    cmd = { "grok" },
    url = "https://github.com/superagent-ai/grok-cli",
  },
  {
    name = "omp",
    cmd = { "omp" },
    title = omp_title,
    url = "https://omp.sh/",
  },
  {
    name = "pi",
    cmd = { "pi" },
    url = "https://pi.dev/",
  },
  {
    name = "q",
    cmd = { "q" },
    url = "https://github.com/aws/amazon-q-developer-cli",
  },
  {
    name = "qwen",
    cmd = { "qwen" },
    location = qwen_location,
    url = "https://github.com/QwenLM/qwen-code",
  },
}

---@type table<string, gents.Tool>
M.defaults = {}
for _, tool in ipairs(builtins) do
  M.defaults[tool.name] = tool
end

---@param configured_tools table<string, gents.Tool>
---@return string[]
function M.names(configured_tools)
  ---@type string[]
  local names = vim.tbl_keys(configured_tools)
  table.sort(names)
  return names
end

return M
