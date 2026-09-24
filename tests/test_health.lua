local test = require("mini.test")
local expect = test.expect.equality
local config = require("gents.config")
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
  vim.cmd("checkhealth gents")
  local buf = vim.api.nvim_get_current_buf()
  -- Asynchronous health checks set the filetype after writing the report.
  assert(
    vim.wait(2000, function()
      return vim.bo[buf].filetype == "checkhealth"
    end, 10),
    "Timed out waiting for health report"
  )
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

---@param value string
---@param text string
---@return boolean
local function contains(value, text)
  return value:find(text, 1, true) ~= nil
end

---@param overrides? table<string, gents.ToolOverride|false>
---@return gents.Config
local function only_tools(overrides)
  ---@type table<string, gents.ToolOverride|false>
  local tools = {}
  for name in pairs(require("gents.tools").defaults) do
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
      cmd = { "gents-test-nonexistent-executable" },
      url = "https://example.com/install-missing",
    },
    no_url = { cmd = { "gents-test-nonexistent-without-url" } },
    disabled = { cmd = { "gents-test-disabled" }, enabled = false },
  })
  local output = report()
  expect(contains(output, "available: executable found (" .. vim.v.progpath .. ")"), true)
  expect(
    contains(output, "missing: executable not found (gents-test-nonexistent-executable)"),
    true
  )
  expect(contains(output, "Install: https://example.com/install-missing"), true)
  expect(contains(output, "Install gents-test-nonexistent-without-url"), true)
  expect(contains(output, "disabled:"), false)
  expect(contains(output, "claude:"), false)
  expect(require("gents").sessions(), {})
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

T["report checks the configured Telescope dependency"] = test.new_set({
  parametrize = { { true }, { false } },
}, {
  ---@param available boolean
  ["reports availability without opening a picker"] = function(available)
    -- Opening a menu needs these modules, which in turn need plenary.nvim.
    local modules = {
      "telescope.pickers",
      "telescope.finders",
      "telescope.config",
      "telescope.actions",
      "telescope.actions.set",
      "telescope.actions.state",
    }
    for _, name in ipairs(modules) do
      ---@type table?
      local loaded = rawget(package.loaded, name)
      ---@type (fun(name: string): unknown)?
      local preload = rawget(package.preload, name)
      test.finally(function()
        rawset(package.loaded, name, loaded)
        rawset(package.preload, name, preload)
      end)
      rawset(package.loaded, name, nil)
      rawset(package.preload, name, function()
        -- Plenary is the usual missing piece: only the last module fails.
        assert(available or name ~= "telescope.actions.state", "plenary.async is unavailable")
        return {}
      end)
    end
    only_tools().picker = "telescope"
    local output = report()
    expect(contains(output, "Using Telescope picker"), available)
    expect(contains(output, "telescope.nvim or plenary.nvim is unavailable"), not available)
    if not available then
      expect(contains(output, "Install nvim-telescope/telescope.nvim"), true)
    end
  end,
})

T["report checks the configured fzf-lua dependencies"] = test.new_set({
  parametrize = { { "available" }, { "no module" }, { "no binary" } },
}, {
  ---@param state string
  ["reports availability without opening a picker"] = function(state)
    local binary = state == "no binary" and vim.fn.tempname() or vim.v.progpath
    -- A missing configured binary falls back to fzf on PATH; keep PATH empty.
    local path = assert(os.getenv("PATH"))
    test.finally(function()
      vim.fn.setenv("PATH", path)
    end)
    vim.fn.setenv("PATH", vim.fn.tempname())
    local stubs = {
      ["fzf-lua"] = { fzf_exec = function() end },
      ["fzf-lua.config"] = { globals = { keymap = {}, fzf_bin = binary } },
      ["fzf-lua.utils"] = {
        ansi_from_hl = function(_, text)
          return text
        end,
      },
    }
    for name, stub in pairs(stubs) do
      ---@type table?
      local loaded = rawget(package.loaded, name)
      ---@type (fun(name: string): unknown)?
      local preload = rawget(package.preload, name)
      test.finally(function()
        rawset(package.loaded, name, loaded)
        rawset(package.preload, name, preload)
      end)
      rawset(package.loaded, name, nil)
      rawset(package.preload, name, function()
        assert(state ~= "no module", "fzf-lua is unavailable for this test")
        return stub
      end)
    end
    only_tools().picker = "fzf-lua"
    local output = report()
    expect(contains(output, "Using fzf-lua picker (" .. binary .. ")"), state == "available")
    expect(contains(output, "fzf-lua is unavailable"), state == "no module")
    expect(contains(output, "fzf executable was not found"), state == "no binary")
  end,
})

T["report warns about invalid picker values"] = function()
  local configured = only_tools()
  for _, picker in ipairs({ false, "unknown", {} }) do
    -- Deliberately corrupt the picker to exercise the health warning.
    ---@diagnostic disable-next-line: assign-type-mismatch
    configured.picker = picker
    local output = report()
    expect(
      contains(
        output,
        'picker must be nil, "snacks", "mini", "telescope", "fzf-lua", or a function'
      ),
      true
    )
    expect(contains(output, "Set picker to nil to use vim.ui.select."), true)
  end
end

return T
