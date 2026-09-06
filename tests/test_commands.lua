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
---@type { [1]: string, [2]: (agents.Target|agents.NewOptions|agents.Item[])[] }[]
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
        ---@param ... agents.Target|agents.NewOptions|agents.Item[]
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

dispatch["ranges are rejected for commands other than send"] = function()
  for _, command in ipairs({ "actions", "new cat" }) do
    test.expect.error(function()
      vim.cmd("1Agents " .. command)
    end, "only send accepts a range")
  end
  expect(calls, {})
end

dispatch["arguments split on whitespace without evaluation"] = function()
  vim.cmd(
    [[Agents new cat   'two words' $HOME $(echo unsafe) | let g:agents_commands_evaluated = 1]]
  )
  expect(calls, {
    {
      "new",
      {
        "cat",
        {
          args = {
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

dispatch["hide and close accept ids and labels containing spaces"] = function()
  vim.cmd("Agents hide 12")
  vim.cmd("Agents close cat   #2")
  expect(calls, { { "hide", { 12 } }, { "close", { "cat #2" } } })
end

dispatch["invalid commands and extra arguments fail clearly"] = function()
  test.expect.error(function()
    vim.cmd("Agents unknown")
  end, "unknown command 'unknown'")
  for _, command in ipairs({ "actions", "pick", "toggle" }) do
    test.expect.error(function()
      vim.cmd("Agents " .. command .. " cat")
    end, command .. " does not accept arguments")
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
  expect(complete("Agents "), { "actions", "close", "hide", "new", "pick", "send", "toggle" })
  expect(complete("Agents a"), { "actions" })
  expect(complete("Agents n"), { "new" })
  expect(complete("Agents actions "), {})
  expect(complete("Agents toggle "), {})
  expect(complete("Agents pick "), {})
  expect(complete("Agents unknown "), {})
end

T["command names are returned independently"] = function()
  local names = commands.names()
  expect(names, { "actions", "close", "hide", "new", "pick", "send", "toggle" })
  table.remove(names, 1)
  expect(commands.names(), { "actions", "close", "hide", "new", "pick", "send", "toggle" })
end

T["send completes providers and prompts at every item position"] = function()
  config.setup({ prompts = { explain = { "file" }, file = { { text = "File prompt" } } } })
  expect(complete("Agents send fi"), { "file" })
  expect(complete("Agents send file ex"), { "explain" })
  expect(complete("'<,'>Agents send se"), { "selection" })
  expect(vim.fn.getcompletion("Agents send file di", "cmdline"), { "diagnostics" })
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
end

local H = require("tests.helpers")
local sessions = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
T["sessions"] = sessions

sessions["new, hide, and close operate on a real terminal"] = function()
  vim.cmd("Agents new cat")
  local session = assert(require("agents").current())
  expect(session.tool.name, "cat")
  expect(vim.fn.jobwait({ session.job }, 0), { -1 })
  vim.cmd("Agents hide " .. session.id)
  expect(vim.fn.win_findbuf(session.buf), {})
  vim.cmd("Agents close " .. session.label)
  expect(require("agents").sessions(), {})
  H.wait(function()
    return not vim.api.nvim_buf_is_valid(session.buf)
  end)
end

sessions["completion replaces only the current word of a session label"] = function()
  H.new()
  H.new()
  H.new({ label = "feature code review" })
  expect(complete("Agents hide "), { "cat", "cat #2", "feature code review" })
  expect(complete("Agents close c"), { "cat", "cat #2" })
  expect(complete("Agents close cat "), { "#2" })
  expect(complete("Agents close cat #"), { "#2" })
  expect(complete("Agents close cat   #"), { "#2" })
  expect(complete("Agents hide feature c"), { "code review" })
  expect(complete("Agents hide feature code r"), { "review" })
  expect(complete("Agents close missing"), {})
  expect(vim.fn.getcompletion("Agents close cat #", "cmdline"), { "#2" })
  vim.cmd("Agents close cat #2")
  expect(complete("Agents close cat #"), {})
end

sessions["unknown tools report the requested name"] = function()
  test.expect.error(function()
    vim.cmd("Agents new missing-tool")
  end, "unknown tool: missing%-tool")
  expect(require("agents").sessions(), {})
end

return T
