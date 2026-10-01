local test = require("mini.test")
local expect = test.expect.equality
local commands = require("gents.commands")
local config = require("gents.config")
local T = test.new_set({
  hooks = {
    pre_case = function()
      config.setup()
    end,
    post_case = function()
      config.setup()
    end,
  },
})

---@param line string
---@param lead? string
---@param cursor? integer
---@return string[]
local function complete(line, lead, cursor)
  return commands.complete(lead or assert(line:match("%S*$")), line, cursor or #line)
end

---@type table<string, function>
local original
---@type { [1]: string, [2]: (gents.Target|gents.NewOptions|gents.HideOptions|gents.SendOptions|gents.Item[])[] }[]
local calls
local methods = commands.names()
local dispatch = test.new_set({
  hooks = {
    pre_case = function()
      original, calls = {}, {}
      ---@type table<string, function>
      local gents = require("gents")
      for _, name in ipairs(methods) do
        original[name] = gents[name]
        ---@param ... gents.Target|gents.NewOptions|gents.HideOptions|gents.SendOptions|gents.Item[]
        gents[name] = function(...)
          calls[#calls + 1] = { name, { ... } }
        end
      end
    end,
    post_case = function()
      ---@type table<string, function>
      local gents = require("gents")
      for _, name in ipairs(methods) do
        gents[name] = original[name]
      end
      vim.g.gents_commands_evaluated = nil
    end,
  },
})

T["dispatch"] = dispatch

dispatch["every subcommand calls the Lua facade"] = function()
  for _, command in ipairs({
    "",
    "actions",
    "new",
    "new cat",
    "toggle",
    "focus",
    "pick",
    "hide",
    "close",
    "send",
  }) do
    vim.cmd("Gents " .. command)
  end
  expect(calls, {
    { "pick", {} },
    { "actions", {} },
    { "new", {} },
    { "new", { "cat" } },
    { "toggle", {} },
    { "focus", {} },
    { "pick", {} },
    { "hide", {} },
    { "close", {} },
    { "send", {} },
  })
end

dispatch["send expands named prompts alongside provider names"] = function()
  config.setup({ prompts = { explain = { { text = "Explain:" }, "selection" } } })
  vim.cmd("Gents send file explain")
  expect(calls, { { "send", { { "file", { text = "Explain:" }, "selection" } } } })
end

dispatch["hide all dispatches directly and rejects a target"] = function()
  vim.cmd("Gents hide --all")
  vim.cmd("Gents actions hide --all")
  expect(calls, { { "hide", { [2] = { all = true } } }, { "hide", { [2] = { all = true } } } })
  for _, args in ipairs({ "--all 12", "--all cat", "--all --all" }) do
    test.expect.error(function()
      commands.run({ args = "hide " .. args })
    end, "cannot be combined with a target")
  end
  expect(#calls, 2)
end

dispatch["actions composes with every leaf command"] = function()
  config.setup({ prompts = { explain = { { text = "Explain:" }, "selection" } } })
  for _, command in ipairs({
    "new",
    "new cat --resume --target literal",
    "toggle",
    "toggle cat #2",
    "focus",
    "focus 12",
    "pick",
    "pick cat #2",
    "hide",
    "hide 12",
    "close",
    "close cat #2",
    "send",
    "send file explain",
    "send file explain --target cat #2",
    "send --target 12",
    "send --no-focus",
    "send --no-focus file explain",
    "send file --no-focus explain --target cat #2",
    "send --no-focus --target 12",
  }) do
    calls = {}
    vim.cmd("Gents " .. command)
    local direct = vim.deepcopy(calls)
    calls = {}
    vim.cmd("Gents actions " .. command)
    expect(calls, direct)
  end
end

dispatch["send targets preserve labels and prompt expansion"] = function()
  config.setup({ prompts = { explain = { { text = "Explain:" }, "selection" } } })
  vim.cmd("Gents send file explain --target feature   code review")
  vim.cmd("Gents actions send --target 12")
  expect(calls, {
    {
      "send",
      { { "file", { text = "Explain:" }, "selection" }, { target = "feature code review" } },
    },
    { "send", { nil, { target = 12 } } },
  })
end

dispatch["send accepts a focus opt-out before the target"] = function()
  config.setup({ prompts = { explain = { { text = "Explain:" }, "selection" } } })
  vim.cmd("Gents send --no-focus")
  vim.cmd("Gents send file --no-focus explain")
  vim.cmd("Gents actions send --no-focus file explain --target cat #2")
  vim.cmd("Gents send --no-focus --target 12")
  expect(calls, {
    { "send", { nil, { focus = false } } },
    { "send", { { "file", { text = "Explain:" }, "selection" }, { focus = false } } },
    {
      "send",
      { { "file", { text = "Explain:" }, "selection" }, { focus = false, target = "cat #2" } },
    },
    { "send", { nil, { focus = false, target = 12 } } },
  })
end

dispatch["send preserves option-like text after the target separator"] = function()
  vim.cmd("Gents send file --target feature --no-focus review")
  vim.cmd("Gents actions send --no-focus --target --no-focus")
  expect(calls, {
    { "send", { { "file" }, { target = "feature --no-focus review" } } },
    { "send", { nil, { focus = false, target = "--no-focus" } } },
  })
end

dispatch["ranges are rejected for commands other than send"] = function()
  for _, command in ipairs({ "actions hide", "actions new cat", "focus", "new cat" }) do
    test.expect.error(function()
      vim.cmd("1Gents " .. command)
    end, "only send accepts a range")
  end
  expect(calls, {})
end

dispatch["ranged send chains forward the range and explicit target"] = function()
  local send = require("gents.send")
  local run = send.run
  ---@param callback fun(items?: gents.Item[], opts?: gents.SendOptions, range?: { line1: integer, line2: integer }): gents.Session?
  local function set_run(callback)
    send.run = callback
  end
  ---@type { items?: gents.Item[], opts?: gents.SendOptions, range?: { line1: integer, line2: integer } }[]
  local sent = {}
  set_run(function(items, opts, range)
    sent[#sent + 1] = { items = items, opts = opts, range = range }
  end)
  local ok, err = pcall(function()
    vim.cmd("1Gents actions send file --target cat #2")
    vim.cmd("1Gents send --target 12")
    vim.cmd("1Gents send --no-focus")
    vim.cmd("1Gents actions send file --no-focus --target cat #2")
    vim.cmd("1Gents actions send --no-focus --target 12")
  end)
  set_run(run)
  assert(ok, err)
  expect(sent, {
    { items = { "file" }, opts = { target = "cat #2" }, range = { line1 = 1, line2 = 1 } },
    { items = { "selection" }, opts = { target = 12 }, range = { line1 = 1, line2 = 1 } },
    { items = { "selection" }, opts = { focus = false }, range = { line1 = 1, line2 = 1 } },
    {
      items = { "file" },
      opts = { focus = false, target = "cat #2" },
      range = { line1 = 1, line2 = 1 },
    },
    {
      items = { "selection" },
      opts = { focus = false, target = 12 },
      range = { line1 = 1, line2 = 1 },
    },
  })
end

dispatch["arguments split on whitespace without evaluation"] = function()
  vim.cmd(
    [[Gents new cat --target literal  'two words' $HOME $(echo unsafe) | let g:gents_commands_evaluated = 1]]
  )
  expect(calls, {
    {
      "new",
      {
        "cat",
        {
          args = {
            "--target",
            "literal",
            "'two",
            "words'",
            "$HOME",
            "$(echo",
            "unsafe)",
            "|",
            "let",
            "g:gents_commands_evaluated",
            "=",
            "1",
          },
        },
      },
    },
  })
  expect(vim.g.gents_commands_evaluated, nil)
end

dispatch["all session commands accept ids and labels containing spaces"] = function()
  for _, command in ipairs({ "hide", "close", "pick", "focus", "toggle" }) do
    calls = {}
    vim.cmd("Gents " .. command .. " 12")
    vim.cmd("Gents " .. command .. " cat   #2")
    expect(calls, { { command, { 12 } }, { command, { "cat #2" } } })
  end
end

dispatch["invalid command chains fail before invoking an action"] = function()
  for _, command in ipairs({ "unknown", "actions unknown" }) do
    test.expect.error(function()
      vim.cmd("Gents " .. command)
    end, "unknown command 'unknown'")
  end
  test.expect.error(function()
    vim.cmd("Gents actions actions")
  end, "gents:")
  expect(calls, {})
end

dispatch["send rejects a missing explicit target"] = function()
  for _, command in ipairs({
    "send --target",
    "send file --target",
    "actions send --target",
    "send --no-focus --target",
    "actions send file --no-focus --target",
  }) do
    test.expect.error(function()
      vim.cmd("Gents " .. command)
    end, "target")
  end
  expect(calls, {})
end

T["sourcing the plugin file again replaces its command without resetting config"] = function()
  local configured = config.setup({ layout = "split" })
  vim.g.loaded_gents = nil
  vim.cmd("runtime plugin/gents.lua")
  expect(vim.g.loaded_gents, true)
  expect(config.get(), configured)
  local command = vim.api.nvim_get_commands({ builtin = false }).Gents
  expect(command.nargs, "*")
end

T["completion covers only supported subcommands"] = function()
  expect(
    complete("Gents "),
    { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" }
  )
  expect(complete("Gents a"), { "actions" })
  expect(complete("Gents f"), { "focus" })
  expect(complete("Gents focus "), {})
  expect(complete("Gents n"), { "new" })
  expect(complete("Gents actions "), { "close", "focus", "hide", "new", "pick", "send", "toggle" })
  expect(complete("Gents actions f"), { "focus" })
  expect(complete("Gents actions a"), {})
  expect(complete("Gents actions actions "), {})
  expect(complete("Gents toggle "), {})
  expect(complete("Gents pick "), {})
  expect(complete("Gents unknown "), {})
end

T["command names are returned independently"] = function()
  local names = commands.names()
  expect(names, { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" })
  table.remove(names, 1)
  expect(commands.names(), { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" })
end

T["send completes providers and prompts at every item position"] = function()
  config.setup({ prompts = { explain = { "file" }, file = { { text = "File prompt" } } } })
  expect(complete("Gents send fi"), { "file" })
  expect(complete("Gents send loc"), { "locationlist" })
  expect(complete("Gents send pos"), {})
  expect(complete("Gents send che"), {})
  expect(complete("Gents send hel"), {})
  expect(complete("Gents send file ex"), { "explain" })
  expect(complete("'<,'>Gents send se"), { "selection" })
  expect(vim.fn.getcompletion("Gents send file di", "cmdline"), { "diagnostics" })
  expect(complete("Gents actions send fi"), { "file" })
  expect(complete("Gents actions send file ex"), { "explain" })
  expect(complete("'<,'>Gents actions send se"), { "selection" })
  expect(complete("Gents send file --t"), { "--target" })
  expect(complete("Gents actions send --t"), { "--target" })
  expect(complete("Gents send --"), { "--no-focus", "--target" })
  expect(complete("Gents send file --no"), { "--no-focus" })
  expect(complete("Gents actions send --no"), { "--no-focus" })
  expect(complete("Gents send --no-focus fi"), { "file" })
  expect(complete("Gents actions send --no-focus file ex"), { "explain" })
  expect(complete("Gents send file --no-focus --t"), { "--target" })
  expect(complete("'<,'>Gents actions send --no"), { "--no-focus" })
  expect(vim.fn.getcompletion("Gents actions send file di", "cmdline"), { "diagnostics" })
  expect(vim.fn.getcompletion("Gents actions send file loc", "cmdline"), { "locationlist" })
end

T["tool completion uses configured tools only at the tool position"] = function()
  config.setup({
    tools = {
      claude = false,
      custom = { cmd = { "cat" } },
    },
  })
  expect(complete("Gents new c"), { "codex", "copilot", "crush", "cursor-agent", "custom" })
  expect(complete("Gents new custom "), {})
  expect(complete("Gents new custom --arg"), {})
  expect(complete("Gents new c ignored", "c", #"Gents new c"), {
    "codex",
    "copilot",
    "crush",
    "cursor-agent",
    "custom",
  })
  expect(vim.fn.getcompletion("Gents new cus", "cmdline"), { "custom" })
  expect(complete("Gents actions new c"), { "codex", "copilot", "crush", "cursor-agent", "custom" })
  expect(complete("Gents actions new custom "), {})
  expect(complete("Gents actions new custom --target"), {})
  expect(complete("Gents actions new c ignored", "c", #"Gents actions new c"), {
    "codex",
    "copilot",
    "crush",
    "cursor-agent",
    "custom",
  })
end

local H = require("tests.helpers")
local sessions = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
T["sessions"] = sessions

sessions["composed new, hide, and close operate on a real terminal"] = function()
  vim.cmd("Gents actions new cat")
  local session = assert(require("gents").current())
  expect(session.tool.name, "cat")
  expect(vim.fn.jobwait({ session.job }, 0), { -1 })
  vim.cmd("Gents actions hide " .. session.id)
  expect(vim.fn.win_findbuf(session.buf), {})
  vim.cmd("Gents actions close " .. session.label)
  expect(require("gents").sessions(), {})
  H.wait(function()
    return not vim.api.nvim_buf_is_valid(session.buf)
  end)
end

sessions["completion replaces only the current word of a session label"] = function()
  local first = H.new()
  local second = H.new()
  local custom = H.new({ label = "feature code review" })
  local all = complete("Gents hide ")
  table.sort(all)
  local expected = {
    "--all",
    tostring(first.id),
    tostring(second.id),
    tostring(custom.id),
    "cat",
    "cat #2",
    "feature code review",
  }
  table.sort(expected)
  expect(all, expected)
  expect(complete("Gents close c"), { "cat", "cat #2" })
  expect(complete("Gents close cat "), { "#2" })
  expect(complete("Gents close cat #"), { "#2" })
  expect(complete("Gents close cat   #"), { "#2" })
  expect(complete("Gents hide feature c"), { "code review" })
  expect(complete("Gents hide feature code r"), { "review" })
  expect(complete("Gents close missing"), {})
  expect(vim.fn.getcompletion("Gents close cat #", "cmdline"), { "#2" })
  for _, command in ipairs({
    "hide",
    "close",
    "pick",
    "focus",
    "toggle",
    "send --target",
    "send file --target",
    "send --no-focus --target",
    "send file --no-focus --target",
  }) do
    expect(complete("Gents " .. command .. " feature code r"), { "review" })
    expect(complete("Gents actions " .. command .. " cat   #"), { "#2" })
    expect(complete("Gents " .. command .. " " .. custom.id), { tostring(custom.id) })
  end
  expect(
    vim.fn.getcompletion("Gents actions send file --target feature c", "cmdline"),
    { "code review" }
  )
  vim.cmd("Gents close cat #2")
  expect(complete("Gents close cat #"), {})
end

sessions["hide completion includes only visible targets and the all modifier"] = function()
  local here = H.new({ label = "all" })
  local hidden = H.new({ label = "hidden" })
  require("gents").hide(hidden.id)
  local tab = vim.api.nvim_get_current_tabpage()
  H.new({ layout = "tabnew", label = "elsewhere" })
  vim.api.nvim_set_current_tabpage(tab)
  local candidates = complete("Gents hide ")
  table.sort(candidates)
  local expected = { "--all", tostring(here.id), "all" }
  table.sort(expected)
  expect(candidates, expected)
  expect(complete("Gents actions hide --a"), { "--all" })
  expect(complete("Gents hide --all "), {})
  expect(complete("Gents close h"), { "hidden" })
  vim.cmd("Gents hide all")
  expect(require("gents.window").visible(here), false)
end

sessions["hide preserves option-like label text in targets and completion"] = function()
  local review = H.new({ label = "review --all" })
  local notes = H.new({ label = "review --all notes" })
  local allow = H.new({ label = "--allow" })
  for _, command in ipairs({ "Gents hide ", "Gents actions hide " }) do
    expect(complete(command .. "review --all"), { "--all", "--all notes" })
    expect(complete(command .. "review --all "), { "notes" })
    expect(complete(command .. "review --all n"), { "notes" })
    expect(complete(command .. "--all"), { "--allow", "--all" })
    expect(complete(command .. "--all "), {})
    expect(complete(command .. "--all n"), {})
  end
  vim.cmd("Gents hide review --all")
  expect(require("gents.window").visible(review), false)
  expect(require("gents.window").visible(notes), true)
  expect(require("gents.window").visible(allow), true)
  vim.cmd("Gents actions hide review --all notes")
  expect(require("gents.window").visible(notes), false)
  expect(require("gents.window").visible(allow), true)
end

sessions["send target completion preserves option-like label text"] = function()
  H.new({ label = "feature --no-focus review" })
  H.new({ label = "--no-focus" })
  expect(complete("Gents send --target feature --no"), { "--no-focus review" })
  expect(complete("Gents send --no-focus --target feature --no-focus r"), { "review" })
  expect(complete("Gents actions send file --target --no"), { "--no-focus" })
  expect(complete("Gents send --target --"), { "--no-focus" })
end

sessions["unknown tools report the requested name"] = function()
  test.expect.error(function()
    vim.cmd("Gents new missing-tool")
  end, "unknown tool: missing%-tool")
  expect(require("gents").sessions(), {})
end

return T
