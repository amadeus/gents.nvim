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
  "aider",
  "amp",
  "claude",
  "codex",
  "copilot",
  "crush",
  "cursor-agent",
  "gemini",
  "grok",
  "opencode",
  "opencode2",
  "pi",
  "q",
  "qwen",
}

T["defaults work without setup"] = function()
  ---@type { get: fun(): agents.Config }
  local fresh = dofile("lua/agents/config.lua")
  local result = fresh.get()
  expect(result.layout, "botright vsplit")
  expect(result.float, { width = 0.8, height = 0.8, border = "rounded" })
  expect(result.picker, nil)
  expect(result.picker_help, true)
  expect(result.icons, { visible = "●", hidden = "○" })
  expect(result.on_exit, "keep")
  expect(result.buflisted, false)
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
  expect(result.tools.codex.cmd, { "codex", "-c", 'tui.terminal_title=["thread"]' })
  expect(result.tools.opencode.env, nil)
  expect(result.tools.opencode2.env, nil)
end

T["title parsers can be customized or disabled without changing commands"] = function()
  ---@param title string
  ---@return string?
  local function parse(title)
    return title:match("^Conversation: (.+)$")
  end
  local result = config.setup({
    tools = { claude = { title = false }, custom = { cmd = { "custom" }, title = parse } },
  })
  expect(result.tools.claude.title, false)
  expect(result.tools.claude.cmd, { "claude" })
  expect(result.tools.custom.title, parse)
  expect(type(config.setup().tools.claude.title), "function")
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
  local opts = {
    buflisted = true,
    tools = { claude = { cmd = { "custom-claude" } }, grok = false },
  }
  local original = vim.deepcopy(opts)
  local result = config.setup(opts)
  expect(result.buflisted, true)
  expect(opts, original)
  opts.tools.claude.cmd[1] = "changed-by-caller"
  expect(result.tools.claude.cmd, { "custom-claude" })
  result.tools.claude.cmd[1] = "changed-config"
  expect(tools.defaults.claude.cmd, { "claude" })
  result = config.setup()
  expect(result.buflisted, false)
  expect(result.tools.claude.cmd, { "claude" })
  expect(result.tools.grok.name, "grok")
end

T["icon overrides merge independently without retaining caller tables"] = function()
  local opts = { icons = { visible = "v" } }
  local original = vim.deepcopy(opts)
  local result = config.setup(opts)
  expect(result.icons, { visible = "v", hidden = "○" })
  expect(opts, original)
  opts.icons.visible = "changed-by-caller"
  expect(result.icons.visible, "v")
  result.icons.hidden = "changed-config"
  expect(config.setup({ icons = { hidden = "h" } }).icons, { visible = "●", hidden = "h" })
  expect(
    config.setup({ icons = { visible = "v", hidden = "h" } }).icons,
    { visible = "v", hidden = "h" }
  )
  expect(config.setup().icons, { visible = "●", hidden = "○" })
end

T["icons accept emoji and multiple characters without a width restriction"] = function()
  local icons = { visible = "👀", hidden = "[hidden]" }
  expect(config.setup({ icons = icons }).icons, icons)
end

T["names sort built-in and custom tools together"] = function()
  local result = config.setup({
    tools = {
      claude = false,
      zebra = { cmd = { "zebra" } },
      alpha = { cmd = { "alpha" } },
      grok = { enabled = false },
    },
  })
  expect(tools.names(result.tools), {
    "aider",
    "alpha",
    "amp",
    "codex",
    "copilot",
    "crush",
    "cursor-agent",
    "gemini",
    "grok",
    "opencode",
    "opencode2",
    "pi",
    "q",
    "qwen",
    "zebra",
  })
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

T["setup accepts the built-in and custom picker"] = function()
  expect(config.setup({ picker = "snacks" }).picker, "snacks")
  expect(config.setup({ picker = "mini" }).picker, "mini")
  expect(config.setup({ picker = "telescope" }).picker, "telescope")
  expect(config.setup({ picker = "fzf-lua" }).picker, "fzf-lua")
  local adapter = function() end
  expect(config.setup({ picker = adapter }).picker, adapter)
  expect(config.setup({ picker = "snacks", picker_help = false }).picker_help, false)
  expect(config.setup().picker_help, true)
end

T["invalid configuration fails before replacing current config"] = function()
  local valid = config.setup({ layout = "split" })
  local invalid = {
    { { layout = false }, "layout must be" },
    { { layout = 1 }, "layout must be" },
    { { on_exit = "discard" }, "on_exit must be" },
    { { buflisted = "true" }, "buflisted must be a boolean" },
    { { buflisted = 1 }, "buflisted must be a boolean" },
    { { picker = false }, "picker must be" },
    { { picker = "unknown" }, "picker must be" },
    { { picker = {} }, "picker must be" },
    { { picker_help = "false" }, "picker_help must be a boolean" },
    { { picker_help = {} }, "picker_help must be a boolean" },
    { { icons = false }, "icons must be" },
    { { icons = "icons" }, "icons must be" },
    { { icons = { visible = false } }, "icons.visible must be" },
    { { icons = { hidden = 1 } }, "icons.hidden must be" },
    { { icons = { visible = "" } }, "icons.visible must be" },
    { { icons = { hidden = "v h" } }, "icons.hidden must be" },
    { { icons = { visible = "v\t" } }, "icons.visible must be" },
    { { icons = { hidden = "h\n" } }, "icons.hidden must be" },
    { { icons = { visible = "\27[31mv" } }, "icons.visible must be" },
    { { icons = { hidden = "h\0" } }, "icons.hidden must be" },
    { { prompts = false }, "prompts must be" },
    { { prompts = { [1] = { "file" } } }, "prompt names must be" },
    { { prompts = { ["two words"] = { "file" } } }, "prompt names must be" },
    { { prompts = { empty = {} } }, "prompts.empty must be" },
    { { tools = { claude = { location = true } } }, "tools.claude.location must be" },
    { { tools = { claude = { title = true } } }, "tools.claude.title must be" },
    { { tools = { claude = { title = "title" } } }, "tools.claude.title must be" },
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
