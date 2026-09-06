local test = require("mini.test")
local expect = test.expect.equality
local commands = require("agents.commands")
local config = require("agents.config")
local T = test.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      commands.setup()
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
---@type { [1]: string, [2]: (agents.Target|agents.NewOptions|agents.SendOptions|agents.Item[])[] }[]
local calls
local methods = commands.names()
local dispatch = test.new_set({
  hooks = {
    pre_case = function()
      original, calls = {}, {}
      ---@type table<string, function>
      local agents = require("agents")
      for _, name in ipairs(methods) do
        original[name] = agents[name]
        ---@param ... agents.Target|agents.NewOptions|agents.SendOptions|agents.Item[]
        agents[name] = function(...)
          calls[#calls + 1] = { name, { ... } }
        end
      end
    end,
    post_case = function()
      ---@type table<string, function>
      local agents = require("agents")
      for _, name in ipairs(methods) do
        agents[name] = original[name]
      end
      vim.g.agents_commands_evaluated = nil
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
    vim.cmd("Agents " .. command)
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
  vim.cmd("Agents send file explain")
  expect(calls, { { "send", { { "file", { text = "Explain:" }, "selection" } } } })
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
    vim.cmd("Agents " .. command)
    local direct = vim.deepcopy(calls)
    calls = {}
    vim.cmd("Agents actions " .. command)
    expect(calls, direct)
  end
end

dispatch["send targets preserve labels and prompt expansion"] = function()
  config.setup({ prompts = { explain = { { text = "Explain:" }, "selection" } } })
  vim.cmd("Agents send file explain --target feature   code review")
  vim.cmd("Agents actions send --target 12")
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
  vim.cmd("Agents send --no-focus")
  vim.cmd("Agents send file --no-focus explain")
  vim.cmd("Agents actions send --no-focus file explain --target cat #2")
  vim.cmd("Agents send --no-focus --target 12")
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
  vim.cmd("Agents send file --target feature --no-focus review")
  vim.cmd("Agents actions send --no-focus --target --no-focus")
  expect(calls, {
    { "send", { { "file" }, { target = "feature --no-focus review" } } },
    { "send", { nil, { focus = false, target = "--no-focus" } } },
  })
end

dispatch["ranges are rejected for commands other than send"] = function()
  for _, command in ipairs({ "actions hide", "actions new cat", "focus", "new cat" }) do
    test.expect.error(function()
      vim.cmd("1Agents " .. command)
    end, "only send accepts a range")
  end
  expect(calls, {})
end

dispatch["ranged send chains forward the range and explicit target"] = function()
  local send = require("agents.send")
  local run = send.run
  ---@param callback fun(items?: agents.Item[], opts?: agents.SendOptions, range?: { line1: integer, line2: integer }): agents.Session?
  local function set_run(callback)
    send.run = callback
  end
  ---@type { items?: agents.Item[], opts?: agents.SendOptions, range?: { line1: integer, line2: integer } }[]
  local sent = {}
  set_run(function(items, opts, range)
    sent[#sent + 1] = { items = items, opts = opts, range = range }
  end)
  local ok, err = pcall(function()
    vim.cmd("1Agents actions send file --target cat #2")
    vim.cmd("1Agents send --target 12")
    vim.cmd("1Agents send --no-focus")
    vim.cmd("1Agents actions send file --no-focus --target cat #2")
    vim.cmd("1Agents actions send --no-focus --target 12")
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
    [[Agents new cat --target literal  'two words' $HOME $(echo unsafe) | let g:agents_commands_evaluated = 1]]
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
            "g:agents_commands_evaluated",
            "=",
            "1",
          },
        },
      },
    },
  })
  expect(vim.g.agents_commands_evaluated, nil)
end

dispatch["all session commands accept ids and labels containing spaces"] = function()
  for _, command in ipairs({ "hide", "close", "pick", "focus", "toggle" }) do
    calls = {}
    vim.cmd("Agents " .. command .. " 12")
    vim.cmd("Agents " .. command .. " cat   #2")
    expect(calls, { { command, { 12 } }, { command, { "cat #2" } } })
  end
end

dispatch["invalid command chains fail before invoking an action"] = function()
  for _, command in ipairs({ "unknown", "actions unknown" }) do
    test.expect.error(function()
      vim.cmd("Agents " .. command)
    end, "unknown command 'unknown'")
  end
  test.expect.error(function()
    vim.cmd("Agents actions actions")
  end, "agents:")
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
      vim.cmd("Agents " .. command)
    end, "target")
  end
  expect(calls, {})
end

T["setup replaces its command without resetting config"] = function()
  local configured = config.setup({ layout = "split" })
  commands.setup()
  commands.setup()
  expect(config.get(), configured)
  local command = vim.api.nvim_get_commands({ builtin = false }).Agents
  expect(command.nargs, "*")
end

T["completion covers only supported subcommands"] = function()
  expect(
    complete("Agents "),
    { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" }
  )
  expect(complete("Agents a"), { "actions" })
  expect(complete("Agents f"), { "focus" })
  expect(complete("Agents focus "), {})
  expect(complete("Agents n"), { "new" })
  expect(complete("Agents actions "), { "close", "focus", "hide", "new", "pick", "send", "toggle" })
  expect(complete("Agents actions f"), { "focus" })
  expect(complete("Agents actions a"), {})
  expect(complete("Agents actions actions "), {})
  expect(complete("Agents toggle "), {})
  expect(complete("Agents pick "), {})
  expect(complete("Agents unknown "), {})
end

T["command names are returned independently"] = function()
  local names = commands.names()
  expect(names, { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" })
  table.remove(names, 1)
  expect(commands.names(), { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" })
end

T["send completes providers and prompts at every item position"] = function()
  config.setup({ prompts = { explain = { "file" }, file = { { text = "File prompt" } } } })
  expect(complete("Agents send fi"), { "file" })
  expect(complete("Agents send file ex"), { "explain" })
  expect(complete("'<,'>Agents send se"), { "selection" })
  expect(vim.fn.getcompletion("Agents send file di", "cmdline"), { "diagnostics" })
  expect(complete("Agents actions send fi"), { "file" })
  expect(complete("Agents actions send file ex"), { "explain" })
  expect(complete("'<,'>Agents actions send se"), { "selection" })
  expect(complete("Agents send file --t"), { "--target" })
  expect(complete("Agents actions send --t"), { "--target" })
  expect(complete("Agents send --"), { "--no-focus", "--target" })
  expect(complete("Agents send file --no"), { "--no-focus" })
  expect(complete("Agents actions send --no"), { "--no-focus" })
  expect(complete("Agents send --no-focus fi"), { "file" })
  expect(complete("Agents actions send --no-focus file ex"), { "explain" })
  expect(complete("Agents send file --no-focus --t"), { "--target" })
  expect(complete("'<,'>Agents actions send --no"), { "--no-focus" })
  expect(vim.fn.getcompletion("Agents actions send file di", "cmdline"), { "diagnostics" })
end

T["tool completion uses configured tools only at the tool position"] = function()
  config.setup({
    tools = {
      claude = false,
      custom = { cmd = { "cat" } },
    },
  })
  expect(complete("Agents new c"), { "codex", "copilot", "crush", "cursor-agent", "custom" })
  expect(complete("Agents new custom "), {})
  expect(complete("Agents new custom --arg"), {})
  expect(complete("Agents new c ignored", "c", #"Agents new c"), {
    "codex",
    "copilot",
    "crush",
    "cursor-agent",
    "custom",
  })
  expect(vim.fn.getcompletion("Agents new cus", "cmdline"), { "custom" })
  expect(
    complete("Agents actions new c"),
    { "codex", "copilot", "crush", "cursor-agent", "custom" }
  )
  expect(complete("Agents actions new custom "), {})
  expect(complete("Agents actions new custom --target"), {})
  expect(complete("Agents actions new c ignored", "c", #"Agents actions new c"), {
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
  vim.cmd("Agents actions new cat")
  local session = assert(require("agents").current())
  expect(session.tool.name, "cat")
  expect(vim.fn.jobwait({ session.job }, 0), { -1 })
  vim.cmd("Agents actions hide " .. session.id)
  expect(vim.fn.win_findbuf(session.buf), {})
  vim.cmd("Agents actions close " .. session.label)
  expect(require("agents").sessions(), {})
  H.wait(function()
    return not vim.api.nvim_buf_is_valid(session.buf)
  end)
end

sessions["completion replaces only the current word of a session label"] = function()
  local first = H.new()
  local second = H.new()
  local custom = H.new({ label = "feature code review" })
  local all = complete("Agents hide ")
  table.sort(all)
  local expected = {
    tostring(first.id),
    tostring(second.id),
    tostring(custom.id),
    "cat",
    "cat #2",
    "feature code review",
  }
  table.sort(expected)
  expect(all, expected)
  expect(complete("Agents close c"), { "cat", "cat #2" })
  expect(complete("Agents close cat "), { "#2" })
  expect(complete("Agents close cat #"), { "#2" })
  expect(complete("Agents close cat   #"), { "#2" })
  expect(complete("Agents hide feature c"), { "code review" })
  expect(complete("Agents hide feature code r"), { "review" })
  expect(complete("Agents close missing"), {})
  expect(vim.fn.getcompletion("Agents close cat #", "cmdline"), { "#2" })
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
    expect(complete("Agents " .. command .. " feature code r"), { "review" })
    expect(complete("Agents actions " .. command .. " cat   #"), { "#2" })
    expect(complete("Agents " .. command .. " " .. custom.id), { tostring(custom.id) })
  end
  expect(
    vim.fn.getcompletion("Agents actions send file --target feature c", "cmdline"),
    { "code review" }
  )
  vim.cmd("Agents close cat #2")
  expect(complete("Agents close cat #"), {})
end

sessions["send target completion preserves option-like label text"] = function()
  H.new({ label = "feature --no-focus review" })
  H.new({ label = "--no-focus" })
  expect(complete("Agents send --target feature --no"), { "--no-focus review" })
  expect(complete("Agents send --no-focus --target feature --no-focus r"), { "review" })
  expect(complete("Agents actions send file --target --no"), { "--no-focus" })
  expect(complete("Agents send --target --"), { "--no-focus" })
end

sessions["unknown tools report the requested name"] = function()
  test.expect.error(function()
    vim.cmd("Agents new missing-tool")
  end, "unknown tool: missing%-tool")
  expect(require("agents").sessions(), {})
end

return T
