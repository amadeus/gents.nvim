local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local eq = test.expect.equality

---@type agents.TitleEvent[]
local observed = {}
---@type table<integer, integer>
local requests = {}
local ready_count = 0
---@type integer
local group

---@param title string
---@param _session agents.Session
---@return string?
local function parse(title, _session)
  if title ~= "reset" then
    return title
  end
end

---@param tool? string
---@param code? integer
---@param terminator? string
---@return agents.test.Session
local function new_stream(tool, code, terminator)
  local cmd = {
    "sh",
    "-c",
    [[
        while IFS= read -r title; do
          [ "$title" = "__exit__" ] && exit 0
          printf '\033]%s;%s%b' "$1" "$title" "$2"
        done
      ]],
    "sh",
    tostring(code or 2),
    terminator or "\\007",
  }
  if tool == "codex" then
    -- The shell fixture replaces argv; retain the built-in title configuration.
    vim.list_extend(cmd, { "-c", 'tui.terminal_title=["thread"]' })
  end
  local session = assert(agents.new(tool or "cat", { cmd = cmd }))
  assert(session.job and session.job > 0)
  ---@cast session agents.test.Session
  return session
end

---@param session agents.test.Session
---@param titles string[]
local function send(session, titles)
  local expected = (requests[session.buf] or 0) + #titles
  vim.fn.chansend(session.job, table.concat(titles, "\n") .. "\n")
  H.wait(function()
    return (requests[session.buf] or 0) >= expected
  end)
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      require("agents.config").get().tools.cat.title = parse
      observed, requests, ready_count = {}, {}, 0
      group = vim.api.nvim_create_augroup("AgentsTitlesTest", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "AgentsSessionTitle",
        callback = function(ev)
          observed[#observed + 1] = vim.deepcopy(ev.data)
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "AgentsReady",
        callback = function()
          ready_count = ready_count + 1
        end,
      })
      vim.api.nvim_create_autocmd("TermRequest", {
        group = group,
        callback = function(ev)
          ---@type vim.event.termrequest.data
          local data = ev.data
          if data.sequence:match("^\027%][02];") then
            requests[ev.buf] = (requests[ev.buf] or 0) + 1
          end
        end,
      })
    end,
    post_case = function()
      vim.api.nvim_del_augroup_by_id(group)
      H.reset()
    end,
  },
})

T["OSC title transport"] = test.new_set({
  parametrize = { { 0, "\\007" }, { 0, "\\033\\\\" }, { 2, "\\007" }, { 2, "\\033\\\\" } },
}, {
  ---@param code integer
  ---@param terminator string
  ["updates metadata without renaming the buffer or signaling ready"] = function(code, terminator)
    local session = new_stream(nil, code, terminator)
    local name, label = vim.api.nvim_buf_get_name(session.buf), session.label
    local before = agents.status()[1]
    send(session, { "Investigate flaky tests" })
    eq(session.title, "Investigate flaky tests")
    eq(agents.status()[1].title, session.title)
    eq(before.title, nil)
    eq(session.label, label)
    eq(vim.api.nvim_buf_get_name(session.buf), name)
    eq(observed, { { id = session.id, title = session.title } })
    eq(ready_count, 0)
  end,
})

T["batched names, renames, resets and resumes emit only actual changes"] = function()
  local session = new_stream()
  send(session, { "First task", "Renamed task", "Renamed task", "reset", "reset", "Resumed task" })
  eq(observed, {
    { id = session.id, title = "First task" },
    { id = session.id, title = "Renamed task" },
    { id = session.id },
    { id = session.id, title = "Resumed task" },
  })
  eq(session.title, "Resumed task")
  eq(ready_count, 0)
end

T["hidden sessions update independently even when their titles match"] = function()
  local first, second = new_stream(), new_stream()
  agents.hide(first.id)
  send(first, { "Shared task" })
  send(second, { "Shared task" })
  send(first, { "Hidden rename" })
  eq({ first.title, second.title }, { "Hidden rename", "Shared task" })
  eq(vim.fn.win_findbuf(first.buf), {})
  eq(observed, {
    { id = first.id, title = "Shared task" },
    { id = second.id, title = "Shared task" },
    { id = first.id, title = "Hidden rename" },
  })
end

T["normalization rejects project-only and empty titles after parsing"] = function()
  require("agents.config").get().tools.cat.title = function(title, session)
    eq(type(session.id), "number")
    eq(title, vim.trim(title))
    if title == "controls" then
      return "Control\tcharacters"
    end
    return title == "whitespace" and " \t\r\n " or "  " .. title .. "  "
  end
  local session = new_stream()
  send(
    session,
    { "  Trim this title  ", session.cwd, "Another task", vim.fs.basename(session.cwd) }
  )
  send(session, { "controls", "whitespace" })
  eq(observed, {
    { id = session.id, title = "Trim this title" },
    { id = session.id },
    { id = session.id, title = "Another task" },
    { id = session.id },
    { id = session.id, title = "Control characters" },
    { id = session.id },
  })
  eq(session.title, nil)
end

T["tool title parsers"] = test.new_set({
  parametrize = {
    { "claude", { "✳ First task", "◐ Renamed task", "Claude Code", "◑ Resumed task" } },
    { "opencode", { "OC | First task", "OC | Renamed task", "OpenCode", "OC | Resumed task" } },
    { "opencode2", { "OC | First task", "OC | Renamed task", "OpenCode", "OC | Resumed task" } },
    {
      "codex",
      { "First task", "Renamed task", "019c6e27-e55b-73d1-87d8-4e01f1f75043", "Resumed task" },
    },
  },
}, {
  ---@param tool string
  ---@param titles string[]
  ["track naming, reset and resume through the terminal"] = function(tool, titles)
    local session = new_stream(tool)
    send(session, titles)
    eq(observed, {
      { id = session.id, title = "First task" },
      { id = session.id, title = "Renamed task" },
      { id = session.id },
      { id = session.id, title = "Resumed task" },
    })
  end,
})

T["built-in parsers only remove known anchored prefixes"] = function()
  local session = new_stream()
  local tools = require("agents.tools").defaults
  local claude, opencode, codex = tools.claude.title, tools.opencode.title, tools.codex.title
  assert(type(claude) == "function" and type(opencode) == "function" and type(codex) == "function")
  eq(claude("Keep ✳ and ◐ in this title", session), "Keep ✳ and ◐ in this title")
  eq(claude("✳ Claude Code", session), nil)
  eq(opencode("Not OC | a conversation", session), nil)
  eq(opencode("OC | Keep OC | in this title", session), "Keep OC | in this title")
  session.cmd = vim.deepcopy(tools.codex.cmd)
  eq(codex("Codex", session), nil)
  eq(codex("019C6E27-E55B-73D1-87D8-4E01F1F75043", session), nil)
  eq(
    codex("Debug 019c6e27-e55b-73d1-87d8-4e01f1f75043", session),
    "Debug 019c6e27-e55b-73d1-87d8-4e01f1f75043"
  )
end

T["Codex only accepts titles when the effective argv selects thread alone"] = function()
  local session = new_stream()
  local parser = require("agents.tools").defaults.codex.title
  assert(type(parser) == "function")
  local thread, project = 'tui.terminal_title=["thread"]', 'tui.terminal_title=["project"]'
  ---@type { cmd: string[], expected?: string }[]
  local cases = {
    { cmd = { "codex" } },
    { cmd = { "codex", "-c", thread }, expected = "Conversation" },
    { cmd = { "codex", "--config", thread }, expected = "Conversation" },
    { cmd = { "codex", "--config=" .. thread }, expected = "Conversation" },
    { cmd = { "codex", "-c" .. thread }, expected = "Conversation" },
    { cmd = { "codex", "-c", thread, "-c", project } },
    { cmd = { "codex", "-c", project, "-c", thread }, expected = "Conversation" },
    { cmd = { "codex", "-c", thread, "--config", "tui={}" } },
  }
  for _, case in ipairs(cases) do
    session.cmd = case.cmd
    eq(parser("Conversation", session), case.expected)
  end
end

T["built-in and custom tools without parsers use cleaned terminal titles"] = function()
  require("agents.config").get().tools.cat.title = nil
  local custom, builtin = new_stream(), new_stream("gemini")
  eq(custom.title, nil)
  eq(builtin.title, nil)
  eq(observed, {})
  send(custom, { "  Custom conversation  " })
  send(builtin, { "Another conversation" })
  eq(custom.title, "Custom conversation")
  eq(builtin.title, "Another conversation")
  eq(observed, {
    { id = custom.id, title = "Custom conversation" },
    { id = builtin.id, title = "Another conversation" },
  })
  send(custom, { custom.cwd })
  eq(custom.title, nil)
  eq(observed[3], { id = custom.id })
end

T["explicit parser opt-outs disable both generic and built-in title reporting"] = function()
  require("agents.config").get().tools.cat.title = false
  require("agents.config").get().tools.claude.title = false
  local custom, builtin = new_stream(), new_stream("claude")
  send(custom, { "Disabled terminal title" })
  send(builtin, { "✳ Disabled title" })
  eq(custom.title, nil)
  eq(builtin.title, nil)
  eq(observed, {})
end

T["exited sessions retain their final title and ignore late requests"] = function()
  local session = H.new({
    cmd = { "sh", "-c", [[printf '\033]2;Final conversation\007\033]2;\007']] },
  })
  H.wait(function()
    return session.state == "exited"
  end)
  vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = session.buf,
    data = { sequence = "\027]2;Late title", terminator = "\007", cursor = { 1, 0 } },
  })
  eq(session.title, "Final conversation")
  eq(agents.status()[1].title, session.title)
  eq(observed, { { id = session.id, title = "Final conversation" } })
end

T["closing a session discards remaining title updates in the same output"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[read signal; printf '\033]2;Close now\007\033]2;Late title\007'; exec cat]],
    },
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AgentsSessionTitle",
    once = true,
    callback = function()
      agents.close(session.id)
    end,
  })
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return session.state == "exited"
  end)
  eq(agents.sessions(), {})
  eq(requests[session.buf], 2)
  eq(session.title, "Close now")
  eq(observed, { { id = session.id, title = "Close now" } })
end

T["ordinary terminal titles do not emit plugin events"] = function()
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.fn.jobstart(
    { "sh", "-c", [[printf '\033]2;Ordinary terminal\007']] },
    { term = true }
  )
  eq(vim.fn.jobwait({ job }, 2000), { 0 })
  H.wait(function()
    return (requests[buf] or 0) == 1
  end)
  eq(observed, {})
  eq(ready_count, 0)
end

return T
