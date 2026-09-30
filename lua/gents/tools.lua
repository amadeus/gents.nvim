local M = {}

-- Title parsers live in gents.titles, which loads with the first reported title
-- rather than at startup.
---@type gents.TitleParser
local function claude_title(title)
  return require("gents.titles").claude(title)
end

---@type gents.TitleParser
local function codex_title(title)
  return require("gents.titles").codex(title)
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

---@param flag string
---@return gents.ResumeArgs
local function resume_flag(flag)
  return function(identifier)
    return { flag, identifier }
  end
end

---@type gents.ResumeArgs
local function aider_resume(identifier, cwd)
  local path = vim.fs.normalize(identifier, { expand_env = false })
  if not path:match("^/") and not path:match("^%a:/") then
    path = vim.fs.joinpath(cwd, path)
  end
  assert(vim.fn.filereadable(path) == 1, "gents: aider history file is not readable: " .. path)
  return { "--chat-history-file", path, "--restore-chat-history" }
end

---@type gents.Tool[]
local builtins = {
  {
    name = "claude",
    cmd = { "claude" },
    resume = resume_flag("--resume"),
    title = claude_title,
    location = claude_location,
    url = "https://code.claude.com/docs/en/quickstart",
  },
  {
    name = "codex",
    cmd = { "codex" },
    resume = resume_flag("resume"),
    title = codex_title,
    url = "https://developers.openai.com/codex/cli",
  },
  {
    name = "opencode",
    cmd = { "opencode" },
    resume = resume_flag("--session"),
    title = opencode_title,
    url = "https://opencode.ai/v2/docs",
  },
  {
    name = "amp",
    cmd = { "amp" },
    resume = function(identifier)
      return { "threads", "continue", identifier }
    end,
    url = "https://ampcode.com/docs/cli",
  },
  {
    name = "aider",
    cmd = { "aider" },
    resume = aider_resume,
    url = "https://aider.chat/docs/install.html",
  },
  {
    name = "copilot",
    cmd = { "copilot", "--banner" },
    resume = function(identifier)
      return { "--resume=" .. identifier }
    end,
    url = "https://github.com/github/copilot-cli",
  },
  {
    name = "crush",
    cmd = { "crush" },
    resume = resume_flag("--session"),
    url = "https://github.com/charmbracelet/crush",
  },
  {
    name = "cursor-agent",
    cmd = { "cursor-agent" },
    resume = resume_flag("--resume"),
    url = "https://cursor.com/docs/cli/installation",
  },
  {
    name = "gemini",
    cmd = { "gemini" },
    resume = resume_flag("--resume"),
    location = gemini_location,
    url = "https://github.com/google-gemini/gemini-cli",
  },
  {
    name = "grok",
    cmd = { "grok" },
    resume = resume_flag("--session"),
    url = "https://github.com/superagent-ai/grok-cli",
  },
  {
    name = "omp",
    cmd = { "omp" },
    resume = resume_flag("--resume"),
    title = omp_title,
    url = "https://omp.sh/",
  },
  {
    name = "pi",
    cmd = { "pi" },
    resume = resume_flag("--session"),
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
    resume = resume_flag("--resume"),
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

---Construct argv before allocating a terminal, and for the picker command editor.
---@param tool gents.Tool
---@param opts gents.NewOptions
---@param cwd string
---@return string[]
function M.command(tool, opts, cwd)
  assert(opts.cmd == nil or opts.args == nil, "gents: cmd and args are mutually exclusive")
  assert(opts.cmd == nil or opts.resume == nil, "gents: cmd and resume are mutually exclusive")
  local cmd = vim.deepcopy(tool.cmd)
  local override = opts.cmd
  if override ~= nil then
    cmd = vim.deepcopy(override)
  end
  assert(
    type(cmd) == "table" and vim.islist(cmd) and #cmd > 0 and cmd[1] ~= "",
    "gents: cmd must be a non-empty list of strings starting with an executable"
  )
  for _, arg in ipairs(cmd) do
    assert(type(arg) == "string", "gents: cmd must be a list of strings")
  end
  if opts.resume ~= nil then
    local identifier = opts.resume
    assert(
      type(identifier) == "string"
        and identifier:find("%S")
        and not identifier:find("%c")
        and identifier:sub(1, 1) ~= "-",
      "gents: resume must be a nonblank string without control characters or a leading '-'"
    )
    assert(type(tool.resume) == "function", "gents: tool does not support resume: " .. tool.name)
    local args = tool.resume(identifier, cwd)
    assert(
      type(args) == "table" and vim.islist(args) and #args > 0,
      "gents: tools." .. tool.name .. ".resume must return a non-empty list of non-empty strings"
    )
    for _, arg in ipairs(args) do
      assert(
        type(arg) == "string" and arg ~= "",
        "gents: tools." .. tool.name .. ".resume must return a non-empty list of non-empty strings"
      )
      cmd[#cmd + 1] = arg
    end
  end
  if opts.args ~= nil then
    assert(
      type(opts.args) == "table" and vim.islist(opts.args),
      "gents: args must be a list of strings"
    )
    for _, arg in ipairs(opts.args) do
      assert(type(arg) == "string", "gents: args must be a list of strings")
      cmd[#cmd + 1] = arg
    end
  end
  return cmd
end

return M
