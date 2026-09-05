local test = require("mini.test")
local expect = test.expect.equality
local config = require("agents.config")
local tools = require("agents.tools")
local T = test.new_set({ hooks = {
  post_case = function()
    config.setup()
  end,
} })

local builtin_names = {
  "claude",
  "codex",
  "opencode",
  "opencode2",
  "amp",
  "aider",
  "copilot",
  "crush",
  "cursor-agent",
  "gemini",
  "grok",
  "pi",
  "q",
  "qwen",
}

T["defaults work without setup"] = function()
  ---@type { get: fun(): agents.Config }
  local fresh = dofile("lua/agents/config.lua")
  local result = fresh.get()
  expect(result.layout, "vsplit")
  expect(result.float, { width = 0.8, height = 0.8, border = "rounded" })
  expect(result.picker, nil)
  expect(result.on_exit, "keep")
  expect(result.prompts, {})
  expect(result.keys, {})
  expect(tools.names(result.tools), builtin_names)
  expect(fresh.get(), result)
end

T["built-in tools have names, commands, and install URLs"] = function()
  local result = config.setup()
  for name, tool in pairs(result.tools) do
    expect(tool.name, name)
    expect(tool.cmd[1], name)
    expect(type(tool.url), "string")
    expect(assert(tool.url):match("^https://") ~= nil, true)
  end
  expect(result.tools.copilot.cmd, { "copilot", "--banner" })
  expect(result.tools.opencode.env, { OPENCODE_THEME = "system" })
  expect(result.tools.opencode2.env, { OPENCODE_THEME = "system" })
end

T["tool overrides replace individual fields and remove names"] = function()
  local result = config.setup({
    float = { border = "single" },
    tools = {
      grok = false,
      copilot = { cmd = { "my-copilot" } },
      opencode = { env = { CUSTOM = "1" } },
      opencode2 = { env = {} },
      custom = { cmd = { "custom", "--tui", "" }, env = { UNSET = false } },
    },
  })
  expect(result.float, { width = 0.8, height = 0.8, border = "single" })
  expect(result.tools.grok, nil)
  expect(result.tools.copilot.cmd, { "my-copilot" })
  expect(result.tools.copilot.url, tools.defaults.copilot.url)
  expect(result.tools.opencode.env, { CUSTOM = "1" })
  expect(result.tools.opencode.cmd, { "opencode" })
  expect(result.tools.opencode2.env, {})
  expect(result.tools.custom, {
    name = "custom",
    cmd = { "custom", "--tui", "" },
    env = { UNSET = false },
  })
end

T["setup resets defaults and does not retain caller tables"] = function()
  local opts = { tools = { claude = { cmd = { "custom-claude" } }, grok = false } }
  local original = vim.deepcopy(opts)
  local result = config.setup(opts)
  expect(opts, original)
  opts.tools.claude.cmd[1] = "changed-by-caller"
  expect(result.tools.claude.cmd, { "custom-claude" })
  result.tools.claude.cmd[1] = "changed-config"
  expect(tools.defaults.claude.cmd, { "claude" })
  result = config.setup()
  expect(result.tools.claude.cmd, { "claude" })
  expect(result.tools.grok.name, "grok")
end

T["names retain built-in order and sort custom tools"] = function()
  local result = config.setup({
    tools = {
      claude = false,
      zebra = { cmd = { "zebra" } },
      alpha = { cmd = { "alpha" } },
      grok = { enabled = false },
    },
  })
  local expected = vim.list_slice(builtin_names, 2)
  vim.list_extend(expected, { "alpha", "zebra" })
  expect(tools.names(result.tools), expected)
  expect(result.tools.grok.enabled, false)
end

T["setup accepts each layout type"] = function()
  for _, layout in ipairs({
    "float",
    { width = 20 },
    function()
      return 1
    end,
  }) do
    expect(config.setup({ layout = layout }).layout, layout)
  end
end

T["invalid configuration fails before replacing current config"] = function()
  local valid = config.setup({ layout = "split" })
  local invalid = {
    { { layout = false }, "layout must be" },
    { { layout = 1 }, "layout must be" },
    { { on_exit = "discard" }, "on_exit must be" },
    { { prompts = false }, "prompts must be" },
    { { prompts = { [1] = { "file" } } }, "prompt names must be" },
    { { prompts = { ["two words"] = { "file" } } }, "prompt names must be" },
    { { prompts = { empty = {} } }, "prompts.empty must be" },
    { { tools = { claude = { location = true } } }, "tools.claude.location must be" },
    { { tools = { claude = { cmd = {} } } }, "tools.claude.cmd must be" },
    { { tools = { claude = { cmd = { "" } } } }, "tools.claude.cmd must be" },
    { { tools = { claude = { cmd = "claude" } } }, "tools.claude.cmd must be" },
    { { tools = { claude = { cmd = { "claude", false } } } }, "tools.claude.cmd must be" },
    {
      { tools = { claude = { cmd = { [1] = "claude", [3] = "arg" } } } },
      "tools.claude.cmd must be",
    },
    { { tools = { custom = {} } }, "tools.custom.cmd must be" },
    { { tools = { custom = true } }, "tools.custom must be" },
  }
  for _, case in ipairs(invalid) do
    local ok, err = pcall(config.setup, case[1])
    expect(ok, false)
    assert(type(err) == "string", "Expected a validation error message")
    expect(err:find(case[2], 1, true) ~= nil, true)
    expect(config.get(), valid)
  end
end

return T
