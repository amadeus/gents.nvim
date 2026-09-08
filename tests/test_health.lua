local test = require("mini.test")
local expect = test.expect.equality
local config = require("agents.config")
local helpers = require("tests.helpers")
local autoread = vim.o.autoread
local T = test.new_set({
  hooks = {
    pre_case = helpers.reset,
    post_case = function()
      vim.o.autoread = autoread
      helpers.reset()
    end,
  },
})

---@return string
local function report()
  vim.cmd("checkhealth agents")
  expect(vim.bo.filetype, "checkhealth")
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

---@param value string
---@param text string
---@return boolean
local function contains(value, text)
  return value:find(text, 1, true) ~= nil
end

---@param overrides? table<string, agents.ToolOverride|false>
---@return agents.Config
local function only_tools(overrides)
  ---@type table<string, agents.ToolOverride|false>
  local tools = {}
  for name in pairs(require("agents.tools").defaults) do
    tools[name] = false
  end
  return config.setup({ tools = vim.tbl_extend("force", tools, overrides or {}) })
end

T["report lists every enabled tool"] = function()
  local configured = config.setup()
  local output = report()
  for name in pairs(configured.tools) do
    expect(contains(output, name .. ": executable "), true)
  end
end

T["executable checks use configured argv and provide installation advice"] = function()
  only_tools({
    available = { cmd = { vim.v.progpath, "--version" } },
    missing = {
      cmd = { "agents-test-nonexistent-executable" },
      url = "https://example.com/install-missing",
    },
    no_url = { cmd = { "agents-test-nonexistent-without-url" } },
    disabled = { cmd = { "agents-test-disabled" }, enabled = false },
  })
  local output = report()
  expect(contains(output, "available: executable found (" .. vim.v.progpath .. ")"), true)
  expect(
    contains(output, "missing: executable not found (agents-test-nonexistent-executable)"),
    true
  )
  expect(contains(output, "Install: https://example.com/install-missing"), true)
  expect(contains(output, "Install agents-test-nonexistent-without-url"), true)
  expect(contains(output, "disabled:"), false)
  expect(contains(output, "claude:"), false)
  expect(require("agents").sessions(), {})
end

T["report handles no enabled tools"] = function()
  only_tools()
  expect(contains(report(), "No tools are enabled."), true)
end

T["report warns when autoread is off and does not change it"] = function()
  only_tools()
  vim.o.autoread = false
  local output = report()
  expect(contains(output, "autoread is disabled"), true)
  expect(contains(output, ":set autoread"), true)
  expect(vim.o.autoread, false)

  vim.o.autoread = true
  output = report()
  expect(contains(output, "autoread is enabled"), true)
  expect(contains(output, "autoread is disabled"), false)
end

T["report accepts the default and custom picker"] = function()
  local configured = only_tools()
  expect(contains(report(), "Using vim.ui.select"), true)
  configured.picker = function()
    error("Health must not open the picker")
  end
  expect(contains(report(), "Using a custom picker function"), true)
end

T["report checks the configured Snacks dependency"] = test.new_set({
  parametrize = { { true }, { false } },
}, {
  ---@param available boolean
  ["reports availability without opening a picker"] = function(available)
    ---@type table?
    local loaded = rawget(package.loaded, "snacks")
    ---@type (fun(name: string): unknown)?
    local preload = rawget(package.preload, "snacks")
    test.finally(function()
      rawset(package.loaded, "snacks", loaded)
      rawset(package.preload, "snacks", preload)
    end)
    rawset(package.loaded, "snacks", nil)
    rawset(package.preload, "snacks", function()
      assert(available, "Snacks is unavailable for this test")
      return {
        picker = function()
          error("Health must not open the picker")
        end,
      }
    end)
    only_tools().picker = "snacks"
    local output = report()
    expect(contains(output, "Using Snacks picker"), available)
    expect(contains(output, "snacks.nvim is unavailable"), not available)
    if not available then
      expect(contains(output, "Install and configure folke/snacks.nvim"), true)
    end
  end,
})

T["report checks the configured mini.pick setup"] = test.new_set({
  parametrize = { { true }, { false } },
}, {
  ---@param available boolean
  ["reports availability without opening a picker"] = function(available)
    ---@type table?
    local loaded = rawget(_G, "MiniPick")
    test.finally(function()
      rawset(_G, "MiniPick", loaded)
    end)
    rawset(_G, "MiniPick", available and {
      start = function()
        error("Health must not open the picker")
      end,
    } or nil)
    only_tools().picker = "mini"
    local output = report()
    expect(contains(output, "Using mini.pick picker"), available)
    expect(contains(output, "mini.pick is not set up"), not available)
    if not available then
      expect(contains(output, 'call require("mini.pick").setup()'), true)
    end
  end,
})

T["report warns about invalid picker values"] = function()
  local configured = only_tools()
  for _, picker in ipairs({ false, "unknown", {} }) do
    -- Deliberately corrupt the picker to exercise the health warning.
    ---@diagnostic disable-next-line: assign-type-mismatch
    configured.picker = picker
    local output = report()
    expect(contains(output, 'picker must be nil, "snacks", "mini", or a function'), true)
    expect(contains(output, "Set picker to nil to use vim.ui.select."), true)
  end
end

return T
