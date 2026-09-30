local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

---@param opts? gents.NewOptions
---@return gents.test.Session
local function new(opts)
  require("gents.config").get().tools.cat.resume = function(identifier)
    return { identifier }
  end
  return H.new(opts)
end

local function save_registers()
  for _, name in ipairs({ '"', "a", "b", "+", "*" }) do
    if name ~= "+" and name ~= "*" then
      local contents = vim.fn.getreginfo(name)
      test.finally(function()
        vim.fn.setreg(name, contents)
      end)
    end
  end
  local clipboard = vim.o.clipboard
  vim.o.clipboard = ""
  test.finally(function()
    vim.o.clipboard = clipboard
  end)
end

T["fresh and resumed selectors require confirmation; switches and guarded clears update it"] = function()
  save_registers()
  local session = new({ cmd = { "cat" } })
  session.resume = "alias"
  vim.fn.setreg("a", "preserved", "V")
  test.expect.error(function()
    gents.copy_reference({ register = "a" })
  end, "has not been reported")
  eq(vim.fn.getreg("a"), "preserved\n")
  eq(gents.report_conversation(session.id, "full-id"), true)
  eq(session.resume, "alias")
  eq(gents.copy_reference({ register = "a" }), "cat:full-id")
  eq(vim.fn.getreg("a"), "cat:full-id")
  eq(vim.fn.getregtype("a"), "v")
  eq(gents.report_conversation(session.id, "fork-id"), true)
  eq(gents.report_conversation(session.id, nil, "full-id"), false)
  eq(gents.copy_reference(), "cat:fork-id")
  eq(vim.fn.getreg('"'), "cat:fork-id")
  eq(gents.report_conversation(session.id, nil, "fork-id"), true)
  test.expect.error(gents.copy_reference, "has not been reported")
end

T["copy requires the invoking registered buffer, regardless of sole or hidden sessions"] = function()
  save_registers()
  local origin = vim.api.nvim_get_current_win()
  local session = new()
  gents.report_conversation(session.id, "saved")
  vim.api.nvim_set_current_win(origin)
  vim.b.gents_session = session.id
  test.expect.error(gents.copy_reference, "requires a Gents session buffer")
  gents.hide(session.id)
  test.expect.error(gents.copy_reference, "requires a Gents session buffer")
end

T["retained exited sessions copy their last confirmation and reject late reports"] = function()
  save_registers()
  local session = new()
  gents.report_conversation(session.id, "saved")
  vim.fn.jobstop(session.job)
  H.wait(function()
    return session.state == "exited"
  end)
  eq(gents.report_conversation(session.id, "late"), false)
  eq(gents.copy_reference(), "cat:saved")
  gents.close(session.id)
  eq(gents.report_conversation(session.id, "closed"), false)
end

T["literal selectors"] = test.new_set({
  parametrize = {
    { "saved.id" },
    { "/path with spaces/[history].md" },
    { '日本語, "quoted"; id' },
  },
}, {
  ---@param identifier string
  ["copy and parse round-trip without changing editor state"] = function(identifier)
    save_registers()
    local session = new()
    gents.report_conversation(session.id, identifier)
    local win, buf, mode =
      vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(), vim.fn.mode()
    local text = gents.copy_reference({ register = "b" })
    eq(require("gents.references").parse(text, 0, require("gents.config").get().tools), {
      tool = "cat",
      identifier = identifier,
    })
    eq(
      { vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(), vim.fn.mode() },
      { win, buf, mode }
    )
    eq(session.conversation, identifier)
  end,
})

T["invalid IDs, disabled adapters, unrepresentable IDs, and invalid registers preserve contents"] = function()
  save_registers()
  local session = new()
  vim.fn.setreg("a", "preserved", "v")
  for _, identifier in ipairs({ "", " ", "-flag", "id\nnext", "id\000next" }) do
    test.expect.error(function()
      gents.report_conversation(session.id, identifier)
    end)
    eq(session.conversation, nil)
  end
  gents.report_conversation(session.id, "unbalanced]")
  test.expect.error(function()
    gents.copy_reference({ register = "a" })
  end, "cannot be represented")
  gents.report_conversation(session.id, "saved")
  for _, register in ipairs({ "A", "ab", "_", "=", "0" }) do
    test.expect.error(function()
      gents.copy_reference({ register = register })
    end, "register must be")
  end
  require("gents.config").get().tools.cat.resume = false
  test.expect.error(function()
    gents.copy_reference({ register = "a" })
  end, "does not support resume")
  eq(vim.fn.getreg("a"), "preserved")
end

T["commands accept only a register and complete copy options"] = function()
  save_registers()
  local session = new()
  gents.report_conversation(session.id, "saved")
  vim.cmd("Gents actions copy --register a")
  eq(vim.fn.getreg("a"), "cat:saved")
  for _, args in ipairs({
    "copy 1",
    "copy --target cat",
    "copy --register",
    "copy --register a extra",
  }) do
    test.expect.error(function()
      require("gents.commands").run({ args = args })
    end, "copy accepts only")
  end
  eq(vim.fn.getcompletion("Gents copy --", "cmdline"), { "--register" })
  eq(vim.fn.getcompletion("Gents actions copy --", "cmdline"), { "--register" })
  eq(vim.fn.getcompletion("Gents copy --register ", "cmdline"), {})
end

T["deferred action refuses another buffer or a closed session"] = function()
  save_registers()
  local source = new()
  gents.report_conversation(source.id, "source")
  ---@type gents.PickerSpec<gents.CommandName>?
  local spec
  require("gents.config").get().picker = function(received)
    spec = received
  end
  gents.actions()
  assert(spec)
  local copy = assert(vim.iter(spec.items):find(function(item)
    return item.data == "copy"
  end))
  local other = new({ layout = "current" })
  gents.report_conversation(other.id, "other")
  test.expect.error(function()
    assert(spec).actions.run(copy)
  end, "source session buffer has changed")
  vim.api.nvim_set_current_buf(source.buf)
  assert(spec).actions.run(copy)
  eq(vim.fn.getreg('"'), "cat:source")
  gents.close(source.id)
  vim.fn.setreg('"', "preserved", "v")
  assert(spec).actions.run(copy)
  eq(vim.fn.getreg('"'), "preserved")
end

T["hook input accepts synchronous main SessionStart and explicit literal reports"] = function()
  local decode = require("gents.hooks").decode
  eq(
    { decode('{"hook_event_name":"SessionStart","session_id":"saved"}', false) },
    { "saved", nil, true }
  )
  eq(
    { decode('{"hook_event_name":"SessionStart","session_id":"child","agent_id":"child"}', false) },
    { nil, nil, false }
  )
  eq({ decode('{"hook_event_name":"Stop","session_id":"old"}', false) }, { nil, nil, false })
  eq({ decode('{"identifier":"literal; quote\\" id"}', true) }, { 'literal; quote" id', nil, true })
  eq({ decode('{"clear":true,"expected":"saved"}', true) }, { nil, "saved", true })
  eq({ decode('{"session_id":"foreground"}', false, true) }, { "foreground", nil, true })
  test.expect.error(function()
    decode('{"identifier":12}', true)
  end)
end

T["a real CLI job reports over RPC to its own terminal without identifier interpolation"] = function()
  save_registers()
  if vim.v.servername == "" then
    local server = vim.fn.serverstart(vim.fn.tempname() .. ".sock")
    test.finally(function()
      vim.fn.serverstop(server)
    end)
  end
  local script = vim.fs.joinpath(vim.fn.getcwd(), "scripts/conversation.lua")
  local identifier = 'literal "quoted"; 日本語'
  local payload = vim.fn.tempname()
  vim.fn.writefile({ vim.json.encode({ identifier = identifier }) }, payload)
  test.finally(function()
    vim.fn.delete(payload)
  end)
  gents.setup({
    tools = {
      hook = {
        cmd = {
          "sh",
          "-c",
          [["$GENTS_TEST_NVIM" --headless --clean -u NONE -i NONE -l "$GENTS_TEST_SCRIPT" report < "$GENTS_TEST_PAYLOAD"; exec cat]],
        },
        env = {
          GENTS_TEST_NVIM = vim.v.progpath,
          GENTS_TEST_SCRIPT = script,
          GENTS_TEST_PAYLOAD = payload,
        },
        resume = function(id)
          return { id }
        end,
      },
    },
  })
  local session = assert(gents.new("hook"))
  H.wait(function()
    return session.conversation ~= nil
  end)
  eq(session.conversation, identifier)
  eq(gents.copy_reference(), 'hook:[literal "quoted"; 日本語]')
end

T["native clipboard providers receive unnamed options and explicit clipboard copies"] = function()
  local channel = vim.fn.jobstart({
    vim.v.progpath,
    "--embed",
    "--headless",
    "--clean",
    "-u",
    vim.fs.joinpath(vim.fn.getcwd(), "tests/minimal_init.lua"),
    "-i",
    "NONE",
  }, { rpc = true })
  assert(channel > 0)
  test.finally(function()
    pcall(
      vim.rpcrequest,
      channel,
      "nvim_exec_lua",
      [[
      for _, session in ipairs(require("gents").sessions()) do require("gents").close(session.id) end
    ]],
      {}
    )
    pcall(vim.rpcrequest, channel, "nvim_command", "qa!")
    if vim.fn.jobwait({ channel }, 1000)[1] == -1 then
      vim.fn.jobstop(channel)
      vim.fn.jobwait({ channel }, 1000)
    end
  end)
  local copies = vim.rpcrequest(
    channel,
    "nvim_exec_lua",
    [[
    local copied = {}
    local function copy(register)
      return function(lines, kind) copied[#copied + 1] = { register, lines, kind } end
    end
    vim.g.clipboard = {
      name = "gents-test", cache_enabled = 0,
      copy = { ["+"] = copy("+"), ["*"] = copy("*") },
      paste = { ["+"] = function() return { {""}, "v" } end,
                ["*"] = function() return { {""}, "v" } end },
    }
    require("gents").setup({ tools = { cat = {
      cmd = {"cat"}, resume = function(id) return {id} end,
    } } })
    local session = require("gents").new("cat")
    require("gents").report_conversation(session.id, "saved")
    vim.o.clipboard = "unnamedplus,unnamed"
    require("gents").copy_reference()
    vim.o.clipboard = ""
    require("gents").copy_reference({register = "+"})
    require("gents").copy_reference({register = "*"})
    return copied
  ]],
    {}
  )
  eq(copies, {
    { "+", { "cat:saved" }, "v" },
    { "*", { "cat:saved" }, "v" },
    { "+", { "cat:saved" }, "v" },
    { "*", { "cat:saved" }, "v" },
  })
end

return T
