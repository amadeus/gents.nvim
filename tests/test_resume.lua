local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local tools = require("gents.tools")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

local selectors = {
  { "claude", { "--resume" } },
  { "codex", { "resume" } },
  { "opencode", { "--session" } },
  { "amp", { "threads", "continue" } },
  { "copilot", { "--resume=" } },
  { "crush", { "--session" } },
  { "cursor-agent", { "--resume" } },
  { "gemini", { "--resume" } },
  { "grok", { "--session" } },
  { "omp", { "--resume" } },
  { "pi", { "--session" } },
  { "qwen", { "--resume" } },
}

T["built-in selectors"] = test.new_set({ parametrize = selectors }, {
  ---@param name string
  ---@param prefix string[]
  ["reach a real job literally after configured argv and before extra args"] = function(
    name,
    prefix
  )
    local identifier = "saved thread; $(not-a-command) $HOME"
    local cmd = { "sh", "-c", 'printf "%s\\n" "$@"', "probe" }
    gents.setup({ tools = { [name] = { cmd = cmd } } })
    local expected = vim.deepcopy(prefix)
    if name == "copilot" then
      expected[1] = expected[1] .. identifier
    else
      expected[#expected + 1] = identifier
    end
    expected[#expected + 1] = "extra argument"
    local opts = {
      resume = identifier,
      args = { "extra argument" },
      label = "restored",
      layout = "current",
    }
    local original = vim.deepcopy(opts)
    local session = assert(gents.new(name, opts))
    H.wait(function()
      return session.state == "exited"
    end)
    eq(session.exit_code, 0)
    eq(session.cmd, vim.list_extend(vim.deepcopy(cmd), expected))
    local output = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
    eq(output:find(table.concat(expected, "\n"), 1, true) ~= nil, true)
    eq(session.resume, identifier)
    eq(session.label, "restored")
    eq(session.tool.cmd, cmd)
    eq(require("gents.config").get().tools[name].cmd, cmd)
    eq(opts, original)
  end,
})

T["Copilot keeps its configured banner and resume uses a fresh terminal each time"] = function()
  eq(
    tools.command(tools.defaults.copilot, { resume = "session" }, vim.fn.getcwd()),
    { "copilot", "--banner", "--resume=session" }
  )
  gents.setup({
    tools = {
      codex = {
        cmd = { "cat" },
        resume = function(id)
          return { id }
        end,
      },
    },
  })
  local path = vim.fn.tempname()
  vim.fn.writefile({ "saved history" }, path)
  test.finally(function()
    vim.fn.delete(path)
  end)
  local first = assert(gents.new("codex", { resume = path }))
  local second = assert(gents.new("codex", { resume = path }))
  eq(second.id, first.id + 1)
  eq(second.buf ~= first.buf, true)
  eq(first.resume, second.resume)
end

T["custom callbacks receive the launch cwd and retain tool metadata"] = function()
  local cwd = vim.fn.getcwd(0)
  local calls = 0
  gents.setup({
    tools = {
      probe = {
        cmd = { "sh", "-c", 'printf "%s\\n" "$GENTS_RESUME_TEST" "$1"', "probe" },
        env = { GENTS_RESUME_TEST = "retained" },
        title = false,
        resume = function(id, directory)
          calls = calls + 1
          eq(directory, cwd)
          return { id }
        end,
      },
    },
  })
  local session = assert(gents.new("probe", { resume = "name", layout = "float" }))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(calls, 1)
  eq(session.cwd, cwd)
  eq(session.tool.title, false)
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
  local output = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
  eq(output:find("retained\nname", 1, true) ~= nil, true)
end

T["normal launches do not invoke resume callbacks and overrides can disable support"] = function()
  gents.setup({
    tools = {
      claude = { cmd = { "cat" }, resume = false },
      codex = {
        cmd = { "cat" },
        resume = function()
          error("resume should not be called")
        end,
      },
    },
  })
  eq(assert(gents.new("claude")).resume, nil)
  eq(assert(gents.new("codex")).resume, nil)
  test.expect.error(function()
    gents.new("claude", { resume = "id" })
  end, "tool does not support resume: claude")
  eq(require("gents.config").setup().tools.claude.resume, tools.defaults.claude.resume)
end

T["invalid selectors, unsupported tools, and callback results fail before allocation"] = function()
  local calls = 0
  ---@type gents.NewOptions
  local opts = {
    layout = function()
      calls = calls + 1
      return vim.api.nvim_get_current_win()
    end,
  }
  local before_bufs, before_wins = vim.api.nvim_list_bufs(), vim.api.nvim_list_wins()
  for _, identifier in ipairs({ false, 1, {}, "", "  ", "-latest", "id\n", "id\0", "id\27" }) do
    rawset(opts, "resume", identifier)
    test.expect.error(function()
      gents.new("codex", opts)
    end, "resume must be a nonblank string")
  end
  opts.resume = "id"
  for _, name in ipairs({ "cat", "q" }) do
    test.expect.error(function()
      gents.new(name, opts)
    end, "tool does not support resume: " .. name)
  end
  opts.cmd = { "cat" }
  test.expect.error(function()
    gents.new("codex", opts)
  end, "cmd and resume are mutually exclusive")
  opts.cmd = nil
  local tool = require("gents.config").get().tools.cat
  for _, result in ipairs({ false, "argv", {}, { "" }, { false }, { [1] = "arg", [3] = "id" } }) do
    rawset(tool, "resume", function()
      return result
    end)
    test.expect.error(function()
      gents.new("cat", opts)
    end, "resume must return a non%-empty list of non%-empty strings")
  end
  rawset(tool, "resume", function()
    error("adapter failure")
  end)
  test.expect.error(function()
    gents.new("cat", opts)
  end, "adapter failure")
  eq(calls, 0)
  eq(gents.sessions(), {})
  eq(vim.api.nvim_list_bufs(), before_bufs)
  eq(vim.api.nvim_list_wins(), before_wins)
end

T["Aider validates literal history paths against the captured launch directory"] = function()
  local directory = vim.fn.tempname()
  vim.fn.mkdir(directory, "p")
  directory = assert(vim.uv.fs_realpath(directory))
  local filename = "saved history $HOME; $(literal).md"
  local path = directory .. "/" .. filename
  vim.fn.writefile({ "history" }, path)
  test.finally(function()
    vim.fn.delete(directory, "rf")
  end)
  gents.setup({ tools = { aider = { cmd = { "sh", "-c", 'printf "%s\\n" "$@"', "probe" } } } })
  local tool = require("gents.config").get().tools.aider
  eq(tools.command(tool, { resume = filename }, directory), {
    "sh",
    "-c",
    'printf "%s\\n" "$@"',
    "probe",
    "--chat-history-file",
    path,
    "--restore-chat-history",
  })
  eq(tools.command(tool, { resume = path }, directory)[6], path)
  local before = vim.api.nvim_list_bufs()
  for _, missing in ipairs({ directory .. "/missing.md", directory }) do
    test.expect.error(function()
      gents.new("aider", { resume = missing })
    end, "aider history file is not readable")
  end
  eq(gents.sessions(), {})
  eq(vim.api.nvim_list_bufs(), before)
  local session = require("gents.session").new(tool, { resume = filename }, directory)
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.cmd[6], path)
  eq(session.resume, filename)
  eq(session.cwd, directory)
end

return T
