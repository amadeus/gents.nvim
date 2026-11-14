local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local tools = require("gents.tools")
local eq = test.expect.equality
local original_input = vim.ui.input
local T = test.new_set({
  hooks = {
    pre_case = H.reset,
    post_case = function()
      vim.ui.input = original_input
      H.reset()
    end,
  },
})

local probe = { "sh", "-c", 'printf "%s\\n" "$@"', "probe" }

-- post_case restores the real function.
---@param callback fun(opts: vim.ui.input.Opts?, on_confirm: fun(input?: string))
local function set_input(callback)
  vim.ui.input = callback
end

---@param opts? gents.SetupOptions
local function setup(opts)
  opts = opts or {}
  opts.tools = vim.tbl_extend("force", {
    probe = { cmd = probe, resume_last = { "--last" } },
    plain = { cmd = probe },
  }, opts.tools or {})
  gents.setup(opts)
end

---@param name string
---@param opts? gents.NewOptions
---@return string[]
local function launch(name, opts)
  local session = assert(gents.new(name, opts))
  H.wait(function()
    return session.state == "exited"
  end)
  return vim.list_slice(session.cmd, #probe + 1)
end

local adapters = {
  { "codex", { "resume", "--last" } },
  { "opencode", { "--continue" } },
  { "aider", { "--restore-chat-history" } },
  { "copilot", { "--continue" } },
  { "crush", { "--continue" } },
  { "gemini", { "--resume", "latest" } },
  { "grok", { "--session", "latest" } },
  { "omp", { "--continue" } },
  { "pi", { "--continue" } },
  { "q", { "chat", "--resume" } },
  { "qwen", { "--continue" } },
}

T["built-in adapters"] = test.new_set({ parametrize = adapters }, {
  ---@param name string
  ---@param expected string[]
  ["continue after the configured command and reach the job"] = function(name, expected)
    setup({ auto_resume = true, tools = { [name] = { cmd = probe } } })
    local session = assert(gents.new(name))
    H.wait(function()
      return session.state == "exited"
    end)
    eq(session.cmd, vim.list_extend(vim.deepcopy(probe), expected))
    local output = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
    eq(output:find(table.concat(expected, "\n"), 1, true) ~= nil, true)
  end,
})

T["tools without an adapter start fresh"] = function()
  local cwd = vim.fn.getcwd()
  setup({ auto_resume = true })
  for _, name in ipairs({ "claude", "amp", "cursor-agent" }) do
    eq(tools.command(require("gents.config").get().tools[name], {}, cwd), tools.defaults[name].cmd)
  end
  eq(launch("plain"), {})
end

T["the setting defaults to off"] = function()
  setup()
  eq(require("gents.config").get().auto_resume, false)
  eq(launch("probe"), {})
  eq(tools.command(tools.defaults.codex, {}, vim.fn.getcwd()), { "codex" })
end

T["tool overrides disable or replace the arguments"] = function()
  setup({
    auto_resume = true,
    tools = {
      probe = { cmd = probe, resume_last = false },
      custom = { cmd = probe, resume_last = { "--pick", "latest one" } },
    },
  })
  eq(launch("probe"), {})
  eq(launch("custom"), { "--pick", "latest one" })
  eq(require("gents.config").setup().tools.codex.resume_last, { "resume", "--last" })
end

T["launches with their own command, conversation, or arguments start as before"] = function()
  setup({
    auto_resume = true,
    tools = {
      probe = {
        cmd = probe,
        resume_last = { "--last" },
        resume = function(id)
          return { "--id", id }
        end,
      },
    },
  })
  eq(launch("probe", { args = { "prompt" } }), { "prompt" })
  eq(launch("probe", { resume = "saved" }), { "--id", "saved" })
  local session = assert(gents.new("probe", { cmd = { "sh", "-c", "exit 0" } }))
  eq(session.cmd, { "sh", "-c", "exit 0" })
  eq(launch("probe", { args = {} }), { "--last" })
end

T["each launch can override the setting"] = function()
  setup({ auto_resume = true })
  eq(launch("probe", { auto_resume = false }), {})
  setup()
  eq(launch("probe", { auto_resume = true }), { "--last" })
  eq(launch("probe", { auto_resume = true, args = { "prompt" } }), { "--last", "prompt" })
  eq(launch("probe", { auto_resume = false, args = { "prompt" } }), { "prompt" })
end

T["invalid settings and unsupported requests fail before allocation"] = function()
  local before_bufs, before_wins = vim.api.nvim_list_bufs(), vim.api.nvim_list_wins()
  for _, value in ipairs({ 1, "yes", {} }) do
    ---@type gents.SetupOptions
    local setup_opts = {}
    rawset(setup_opts, "auto_resume", value)
    test.expect.error(function()
      gents.setup(setup_opts)
    end, "auto_resume must be a boolean")
  end
  for _, value in ipairs({ true, "--last", {}, { "" }, { 1 }, { [1] = "a", [3] = "b" } }) do
    ---@type gents.ToolOverride
    local override = { cmd = probe }
    rawset(override, "resume_last", value)
    test.expect.error(function()
      gents.setup({ tools = { probe = override } })
    end, "resume_last must be a non%-empty list of non%-empty strings or false")
  end
  setup()
  ---@type gents.NewOptions
  local opts = {}
  rawset(opts, "auto_resume", "yes")
  test.expect.error(function()
    gents.new("probe", opts)
  end, "auto_resume must be a boolean")
  test.expect.error(function()
    gents.new("plain", { auto_resume = true })
  end, "tool does not support auto_resume: plain")
  test.expect.error(function()
    gents.new("probe", { auto_resume = true, cmd = { "cat" } })
  end, "auto_resume cannot be combined with cmd or resume")
  rawset(require("gents.config").get().tools.probe, "resume", function(id)
    return { id }
  end)
  test.expect.error(function()
    gents.new("probe", { auto_resume = true, resume = "saved" })
  end, "auto_resume cannot be combined with cmd or resume")
  eq(gents.sessions(), {})
  eq(vim.api.nvim_list_bufs(), before_bufs)
  eq(vim.api.nvim_list_wins(), before_wins)
end

T["command flags precede the tool and later flags reach the CLI"] = function()
  setup({ auto_resume = true })
  vim.cmd("Gents new --no-auto-resume probe")
  eq(vim.list_slice(assert(gents.current()).cmd, #probe + 1), {})
  setup()
  vim.cmd("Gents new --auto-resume probe")
  eq(vim.list_slice(assert(gents.current()).cmd, #probe + 1), { "--last" })
  vim.cmd("Gents new probe --auto-resume")
  eq(vim.list_slice(assert(gents.current()).cmd, #probe + 1), { "--auto-resume" })
  vim.cmd("Gents actions new --auto-resume probe extra")
  eq(vim.list_slice(assert(gents.current()).cmd, #probe + 1), { "--last", "extra" })
end

T["completion offers the flags only before the tool name"] = function()
  setup()
  local commands = require("gents.commands")
  ---@param line string
  ---@return string[]
  local function complete(line)
    return commands.complete(assert(line:match("%S*$")), line, #line)
  end
  eq(complete("Gents new --"), { "--auto-resume", "--no-auto-resume" })
  eq(complete("Gents new --no"), { "--no-auto-resume" })
  eq(vim.tbl_contains(complete("Gents new "), "--auto-resume"), true)
  eq(vim.tbl_contains(complete("Gents new --auto-resume "), "probe"), true)
  eq(vim.tbl_contains(complete("Gents new --auto-resume "), "--no-auto-resume"), false)
  eq(complete("Gents new --auto-resume probe "), {})
  eq(complete("Gents new probe --"), {})
end

---@return fun(): gents.PickerSpec<gents.Tool>
local function capture_tools()
  ---@type gents.PickerSpec<gents.Tool>?
  local captured
  ---@param spec gents.PickerSpec<gents.Tool>
  require("gents.config").get().picker = function(spec)
    captured = spec
  end
  return function()
    return assert(captured)
  end
end

---@param spec gents.PickerSpec<gents.Tool>
---@param name string
---@return gents.PickerItem<gents.Tool>
local function find_tool(spec, name)
  for _, item in ipairs(spec.items) do
    if item.data.name == name then
      return item
    end
  end
  error("tool not found: " .. name)
end

T["the tool picker previews and launches with the arguments"] = function()
  setup({ auto_resume = true, tools = { cat = { cmd = { "cat" }, resume_last = { "--last" } } } })
  local get_spec = capture_tools()
  gents.new()
  local spec = get_spec()
  spec.actions.new(find_tool(spec, "probe"))
  eq(vim.list_slice(assert(gents.current()).cmd, #probe + 1), { "--last" })
  ---@type string?
  local preview
  set_input(function(opts, callback)
    preview = assert(opts).default
    callback(preview)
  end)
  -- An explicit request still launches the edited command exactly once.
  gents.new(nil, { auto_resume = true })
  spec = get_spec()
  spec.actions.edit_args(find_tool(spec, "cat"))
  eq(preview, "cat --last ")
  eq(assert(gents.current()).cmd, { "cat", "--last" })
end

T["an explicit request marks and rejects unsupported tools in the picker"] = function()
  setup()
  local get_spec = capture_tools()
  gents.new(nil, { auto_resume = true })
  local spec = get_spec()
  local plain = find_tool(spec, "plain")
  eq(plain.text:find("Auto-resume unsupported", 1, true) ~= nil, true)
  eq(find_tool(spec, "probe").text:find("unsupported", 1, true), nil)
  test.expect.error(function()
    spec.actions.new(plain)
  end, "tool does not support auto_resume: plain")
  eq(gents.sessions(), {})
end

return T
