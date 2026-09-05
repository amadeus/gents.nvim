local M = {}

---@class agents.Tool
---@field name string
---@field cmd string[]
---@field env? table<string, string|false>
---@field url? string
---@field enabled? boolean

---@type agents.Tool[]
local builtins = {
  {
    name = "claude",
    cmd = { "claude" },
    url = "https://code.claude.com/docs/en/quickstart",
  },
  {
    name = "codex",
    cmd = { "codex" },
    url = "https://developers.openai.com/codex/cli",
  },
  {
    name = "opencode",
    cmd = { "opencode" },
    env = { OPENCODE_THEME = "system" },
    url = "https://opencode.ai/docs/",
  },
  {
    name = "opencode2",
    cmd = { "opencode2" },
    env = { OPENCODE_THEME = "system" },
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
    url = "https://github.com/google-gemini/gemini-cli",
  },
  {
    name = "grok",
    cmd = { "grok" },
    url = "https://github.com/superagent-ai/grok-cli",
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
    url = "https://github.com/QwenLM/qwen-code",
  },
}

---@type table<string, agents.Tool>
M.defaults = {}
for _, tool in ipairs(builtins) do
  M.defaults[tool.name] = tool
end

---@param configured_tools table<string, agents.Tool>
---@return string[]
function M.names(configured_tools)
  local names, custom = {}, {}
  for _, tool in ipairs(builtins) do
    if configured_tools[tool.name] then
      names[#names + 1] = tool.name
    end
  end
  for name in pairs(configured_tools) do
    if not M.defaults[name] then
      custom[#custom + 1] = name
    end
  end
  table.sort(custom)
  vim.list_extend(names, custom)
  return names
end

return M
