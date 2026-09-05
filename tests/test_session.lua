local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
local eq = test.expect.equality

---@param session agents.Session
---@return string
local function output(session)
  return table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
end

T["several real jobs have independent ids, labels, buffers and channels"] = function()
  local first, second = H.new(), H.new()
  eq(second.id > first.id, true)
  eq({ first.label, second.label }, { "cat", "cat #2" })
  eq(first.buf ~= second.buf and first.job ~= second.job, true)
  eq(agents.sessions(), { first, second })
  eq(agents.current(), second)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
  eq(vim.bo[first.buf].buflisted, false)
  eq(vim.bo[first.buf].bufhidden, "hide")
  eq(vim.bo[first.buf].buftype, "terminal")
  eq(vim.bo[first.buf].filetype, "agents_terminal")
  eq(vim.b[first.buf].agents_session, first.id)
  agents.hide(first.id)
  eq(vim.fn.getbufinfo({ buflisted = 1 })[1].bufnr ~= first.buf, true)
  for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    eq(buf.bufnr == first.buf or buf.bufnr == second.buf, false)
  end
  vim.fn.chansend(first.job, "first-session\n")
  H.wait(function()
    return output(first):find("first-session", 1, true) ~= nil
  end)
  eq(output(second):find("first-session", 1, true), nil)
end

T["labels stay unique after close and support explicit labels"] = function()
  local first, second = H.new(), H.new()
  agents.close(first.id)
  local third = H.new()
  eq(third.label, "cat #3")
  local named = H.new({ label = "review" })
  eq(named.label, "review")
  test.expect.error(function()
    H.new({ label = "review" })
  end, "label already exists")
  eq(#agents.sessions(), 3)
  eq(agents.show(second.label), second)
end

T["cwd and environment come from the invoking window and tool"] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  test.finally(function()
    vim.fn.delete(dir, "d")
    vim.env.AGENTS_TEST_REMOVE = nil
  end)
  vim.cmd.lcd(dir)
  vim.env.AGENTS_TEST_REMOVE = "inherited"
  agents.setup({
    tools = {
      probe = {
        cmd = {
          "sh",
          "-c",
          'printf "%s\\n%s|%s|%s\\n%s\\n%s" "$PWD" "$AGENTS_SESSION" "$AGENTS_TEST_VALUE" "${AGENTS_TEST_REMOVE-unset}" "$NVIM" "$TERM"',
        },
        env = {
          AGENTS_TEST_VALUE = "tool-value",
          AGENTS_TEST_REMOVE = false,
          AGENTS_SESSION = "wrong",
        },
      },
    },
  })
  local session = assert(agents.new("probe"))
  H.wait(function()
    return session.state == "exited"
  end)
  local real_dir = assert(vim.uv.fs_realpath(dir))
  eq(vim.uv.fs_realpath(session.cwd), real_dir)
  eq(output(session):gsub("\n", ""):find(real_dir, 1, true) ~= nil, true)
  local expected = tostring(session.id) .. "|tool-value|unset"
  eq(output(session):find(expected, 1, true) ~= nil, true)
  eq(output(session):gsub("\n", ""):find(vim.v.servername, 1, true) ~= nil, true)
  eq(output(session):find("xterm-256color", 1, true) ~= nil, true)
  eq(vim.env.AGENTS_TEST_REMOVE, "inherited")
  eq(assert(require("agents.config").get().tools.probe.env).AGENTS_SESSION, "wrong")
end

T["natural exit keeps the transcript and exit code"] = function()
  agents.setup({ tools = { done = { cmd = { "sh", "-c", "printf finished; exit 7" } } } })
  local session = assert(agents.new("done"))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.exit_code, 7)
  eq(vim.api.nvim_buf_is_valid(session.buf), true)
  eq(vim.bo[session.buf].buflisted, false)
  eq(output(session):find("finished", 1, true) ~= nil, true)
  eq(agents.sessions(), { session })
end

T["close-on-exit removes successful jobs and keeps failed jobs"] = function()
  agents.setup({
    on_exit = "close",
    tools = {
      done = { cmd = { "sh", "-c", "exit 0" } },
      failed = { cmd = { "sh", "-c", "exit 1" } },
    },
  })
  local done, failed = assert(agents.new("done")), assert(agents.new("failed"))
  H.wait(function()
    return not vim.api.nvim_buf_is_valid(done.buf) and failed.state == "exited"
  end)
  eq(done.exit_code, 0)
  eq(failed.exit_code, 1)
  eq(agents.sessions(), { failed })
end

T["close stops a real job and removes the buffer and registry entry"] = function()
  local session = H.new()
  agents.close(session.id)
  eq(agents.sessions(), {})
  eq(vim.fn.win_findbuf(session.buf), {})
  H.wait(function()
    return session.state == "exited" and not vim.api.nvim_buf_is_valid(session.buf)
  end)
  eq(vim.fn.jobwait({ session.job }, 0)[1] ~= -1, true)
  eq(vim.api.nvim_buf_is_valid(session.buf), false)
  eq(agents.sessions(), {})
end

T["native buffer wipe stops the job and removes the session"] = function()
  local session = H.new()
  vim.api.nvim_buf_delete(session.buf, { force = true })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(agents.sessions(), {})
end

T["launch failures leave no session or scratch buffer behind"] = function()
  local before = vim.api.nvim_list_bufs()
  agents.setup({ tools = { missing = { cmd = { "/agents-test/no-such-executable" } } } })
  test.expect.error(function()
    agents.new("missing")
  end)
  eq(agents.sessions(), {})
  eq(vim.api.nvim_list_bufs(), before)
  test.expect.error(function()
    agents.new("missing", { layout = "invalid_agents_layout" })
  end)
  eq(agents.sessions(), {})
  eq(vim.api.nvim_list_bufs(), before)
end

T["additional argv is passed literally and stored without changing defaults"] = function()
  agents.setup({ tools = { probe = { cmd = { "sh", "-c", 'printf "%s" "$1"', "probe" } } } })
  local text = "$(not-a-command); still literal"
  local session = assert(agents.new("probe", { args = { text } }))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.cmd[5], text)
  eq(output(session):find(text, 1, true) ~= nil, true)
  eq(#session.tool.cmd, 4)
end

T["complete argv overrides retain the tool definition and label"] = function()
  local literal = "literal argument with spaces"
  local cmd = { "sh", "-c", 'printf "%s" "$1"', "probe", literal }
  local session = assert(agents.new("cat", { cmd = cmd }))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.cmd, cmd)
  eq(session.tool.cmd, { "cat" })
  eq(session.label, "cat")
  eq(output(session):find(literal, 1, true) ~= nil, true)
  cmd[1] = "changed"
  eq(session.cmd[1], "sh")
end

T["invalid launch argv and mixed cmd args fail before creating a session"] = function()
  local before = vim.api.nvim_list_bufs()
  for _, opts in ipairs({
    { cmd = false },
    { cmd = {} },
    { cmd = { "" } },
    { cmd = { "cat", false } },
    { cmd = { [1] = "cat", [3] = "arg" } },
    { cmd = { "cat" }, args = {} },
    { args = false },
  }) do
    test.expect.error(function()
      -- Deliberately invalid values verify validation before allocating a session.
      ---@diagnostic disable-next-line: param-type-mismatch
      agents.new("cat", opts)
    end)
    eq(agents.sessions(), {})
    eq(vim.api.nvim_list_bufs(), before)
  end
end

return T
