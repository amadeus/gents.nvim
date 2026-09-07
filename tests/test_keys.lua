local test = require("mini.test")
local helpers = require("tests.helpers")
local agents = require("agents")
local eq = test.expect.equality
local T = test.new_set()

---@param keys agents.Keymap[]
local function setup(keys)
  agents.setup({ tools = { cat = { cmd = { "cat" } } }, keys = keys })
end

---@param mode agents.KeyMode
---@param lhs string
---@param buf? integer
---@return vim.api.keyset.get_keymap?
local function mapping(mode, lhs, buf)
  local maps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
  for _, map in ipairs(maps) do
    if map.lhs == lhs then
      return map
    end
  end
end

local config = test.new_set({ hooks = {
  pre_case = helpers.reset,
  post_case = helpers.reset,
} })
T["configuration"] = config

config["default modes are global normal and visual, and local terminal"] = function()
  setup({ { "<F6>", "toggle" } })
  local session = helpers.new()
  eq(type(assert(mapping("n", "<F6>")).callback), "function")
  eq(type(assert(mapping("x", "<F6>")).callback), "function")
  eq(mapping("i", "<F6>"), nil)
  eq(mapping("s", "<F6>"), nil)
  eq(mapping("t", "<F6>"), nil)
  eq(type(assert(mapping("t", "<F6>", session.buf)).callback), "function")
  eq(mapping("n", "<F6>", session.buf), nil)
  eq(mapping("x", "<F6>", session.buf), nil)
end

config["mode overrides support a single mode and a mode list"] = function()
  local invoked = 0
  setup({
    { "<F6>", "hide", mode = "t" },
    {
      "<F7>",
      function()
        invoked = invoked + 1
      end,
      mode = { "n", "i", "x", "s" },
    },
  })
  local session = helpers.new()
  eq(mapping("n", "<F6>"), nil)
  eq(mapping("x", "<F6>"), nil)
  eq(type(assert(mapping("t", "<F6>", session.buf)).callback), "function")
  eq(mapping("t", "<F7>", session.buf), nil)
  assert(assert(mapping("n", "<F7>")).callback)()
  assert(assert(mapping("i", "<F7>")).callback)()
  assert(assert(mapping("x", "<F7>")).callback)()
  assert(assert(mapping("s", "<F7>")).callback)()
  eq(invoked, 4)
end

config["visual-select mappings preserve replacements in either mode"] = function()
  ---@type agents.KeyMode[]
  local selection_modes = { "x", "s" }
  test.finally(function()
    for _, mode in ipairs(selection_modes) do
      pcall(vim.keymap.del, mode, "<F6>")
    end
  end)
  for _, mode in ipairs(selection_modes) do
    setup({ { "<F6>", "toggle", mode = "v" } })
    eq(type(assert(mapping("x", "<F6>")).callback), "function")
    eq(type(assert(mapping("s", "<F6>")).callback), "function")
    local replacement = function() end
    vim.keymap.set(mode, "<F6>", replacement)
    setup({})
    eq(assert(mapping(mode, "<F6>")).callback, replacement)
    eq(mapping(mode == "x" and "s" or "x", "<F6>"), nil)
    vim.keymap.del(mode, "<F6>")
  end
end

config["setup replaces mappings on existing sessions and removes old keys"] = function()
  setup({ { "<F6>", "toggle" } })
  local session = helpers.new()
  setup({ { "<F7>", "hide", mode = "t" } })
  eq(mapping("n", "<F6>"), nil)
  eq(mapping("x", "<F6>"), nil)
  eq(mapping("t", "<F6>", session.buf), nil)
  eq(type(assert(mapping("t", "<F7>", session.buf)).callback), "function")
  setup({})
  eq(mapping("t", "<F7>", session.buf), nil)
end

config["removing configured keys preserves user replacements"] = function()
  setup({ { "<F6>", "toggle" } })
  local session = helpers.new()
  local replacement = function() end
  vim.keymap.set("n", "<F6>", replacement)
  vim.keymap.set("t", "<F6>", replacement, { buffer = session.buf })
  setup({})
  eq(assert(mapping("n", "<F6>")).callback, replacement)
  eq(assert(mapping("t", "<F6>", session.buf)).callback, replacement)
  vim.keymap.del("n", "<F6>")
end

config["invalid keys leave configuration and installed mappings intact"] = function()
  setup({ { "<F6>", "toggle" } })
  local original = require("agents.config").get()
  local callback = assert(mapping("n", "<F6>")).callback
  local invalid = {
    { named = { "<F6>", "toggle" } },
    { false },
    { { "", "toggle" } },
    { { "<F6>", "unknown" } },
    { { "<F6>", "toggle", mode = "invalid" } },
    { { "<F6>", "toggle", mode = { "n", "invalid" } } },
    { { "<F6>", "toggle", mode = false } },
    { { "<F6>", "toggle", mode = { n = true } } },
  }
  for _, keys in ipairs(invalid) do
    local ok, err = pcall(setup, keys)
    eq(ok, false)
    eq(tostring(err):find("agents: keys", 1, true) ~= nil, true)
    eq(require("agents.config").get(), original)
    eq(assert(mapping("n", "<F6>")).callback, callback)
  end
end

config["send opens the context picker"] = function()
  ---@type string?
  local title
  agents.setup({
    keys = { { "<F6>", "send", mode = "n" } },
    ---@param spec agents.PickerSpec<agents.Part[]>
    picker = function(spec)
      title = spec.title
    end,
  })
  assert(assert(mapping("n", "<F6>")).callback)()
  eq(title, "Agents: Send Context")
end

config["actions opens the command picker"] = function()
  ---@type string?
  local title
  agents.setup({
    keys = { { "<F6>", "actions", mode = "n" } },
    ---@param spec agents.PickerSpec<agents.CommandName>
    picker = function(spec)
      title = spec.title
    end,
  })
  assert(assert(mapping("n", "<F6>")).callback)()
  eq(title, "Agents: Actions")
end

config["focus keys move between the editor and a visible session"] = function()
  setup({ { "<F6>", "focus" } })
  local source = vim.api.nvim_get_current_win()
  local session = helpers.new()
  local terminal = vim.api.nvim_get_current_win()

  assert(assert(mapping("t", "<F6>", session.buf)).callback)()
  eq(vim.api.nvim_get_current_win(), source)
  eq(vim.fn.win_findbuf(session.buf), { terminal })

  assert(assert(mapping("n", "<F6>")).callback)()
  eq(vim.api.nvim_get_current_win(), terminal)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

config["FileType mappings can override configured terminal keys"] = function()
  setup({ { "<F6>", "hide" } })
  local replacement = function() end
  local autocmd = vim.api.nvim_create_autocmd("FileType", {
    pattern = "agents_terminal",
    once = true,
    callback = function(event)
      vim.keymap.set("t", "<F6>", replacement, { buffer = event.buf })
    end,
  })
  local session = helpers.new()
  eq(assert(mapping("t", "<F6>", session.buf)).callback, replacement)
  pcall(vim.api.nvim_del_autocmd, autocmd)
end

---@type integer?
local channel
local init = vim.fn.fnamemodify("tests/minimal_init.lua", ":p")

---The executed chunk determines the serialized RPC result's shape.
---@param code string
---@return any
local function lua(code)
  return vim.rpcrequest(assert(channel), "nvim_exec_lua", code, {})
end

---@param keys string
local function input(keys)
  vim.rpcrequest(assert(channel), "nvim_input", keys)
end

---@param code string
local function wait(code)
  eq(
    vim.wait(2000, function()
      return lua("return " .. code)
    end, 10),
    true
  )
end

local input_tests = test.new_set({
  hooks = {
    pre_case = function()
      channel = vim.fn.jobstart({
        vim.v.progpath,
        "--embed",
        "--headless",
        "--clean",
        "-n",
        "-u",
        init,
        "-i",
        "NONE",
      }, { rpc = true })
      assert(channel > 0, "Could not start child Neovim")
      lua([[
      require("agents").setup({
        tools = { cat = { cmd = { "cat" } } },
        keys = { { "<F6>", "toggle" } },
      })
      _G.session = require("agents").new("cat")
    ]])
      wait([[vim.api.nvim_get_mode().mode == "t"]])
    end,
    post_case = function()
      if not channel then
        return
      end
      pcall(
        lua,
        [[
      for _, session in ipairs(require("agents").sessions()) do
        require("agents").close(session.id)
      end
    ]]
      )
      pcall(vim.rpcrequest, channel, "nvim_command", "qa!")
      if vim.fn.jobwait({ channel }, 1000)[1] == -1 then
        vim.fn.jobstop(channel)
        vim.fn.jobwait({ channel }, 1000)
      end
      channel = nil
    end,
  },
})
T["input"] = input_tests

input_tests["toggle works in normal, visual, and session terminal modes"] = function()
  input("<F6>")
  wait([[vim.api.nvim_get_mode().mode == "n" and #vim.fn.win_findbuf(session.buf) == 0]])
  input("<F6>")
  wait([[vim.api.nvim_get_mode().mode == "t" and vim.api.nvim_get_current_buf() == session.buf]])
  input("<F6>")
  wait([[vim.api.nvim_get_mode().mode == "n" and #vim.fn.win_findbuf(session.buf) == 0]])
  input("v")
  wait([[vim.api.nvim_get_mode().mode == "v"]])
  input("<F6>")
  wait([[vim.api.nvim_get_mode().mode == "t" and vim.api.nvim_get_current_buf() == session.buf]])
end

input_tests["plain terminals receive the key without toggling an agents session"] = function()
  input("<F6>")
  wait([[#vim.fn.win_findbuf(session.buf) == 0]])
  lua([[
    vim.cmd.enew()
    _G.plain = vim.api.nvim_get_current_buf()
    _G.plain_job = vim.fn.jobstart({ "cat" }, { term = true })
    vim.cmd.startinsert()
  ]])
  wait([[vim.api.nvim_get_mode().mode == "t"]])
  input("<F6>plain terminal input<CR>")
  wait(
    [[table.concat(vim.api.nvim_buf_get_lines(plain, 0, -1, false), "\n"):find("plain terminal input", 1, true) ~= nil]]
  )
  eq(
    lua(
      [[return { vim.api.nvim_get_current_buf() == plain, #vim.fn.win_findbuf(session.buf), vim.api.nvim_get_mode().mode }]]
    ),
    { true, 0, "t" }
  )
  lua([[vim.fn.jobstop(plain_job)]])
end

input_tests["send captures an active selection and does not reuse it on later invocations"] = function()
  input("<F6>")
  wait([[vim.api.nvim_get_mode().mode == "n"]])
  lua([[
    require("agents").setup({
      tools = { cat = { cmd = { "cat" } } },
      keys = { { "<F7>", "send" } },
      picker = function(spec)
        _G.previews = {}
        for _, item in ipairs(spec.items) do
          local name = item.text:match("^%S+")
          _G.previews[name] = item.preview
        end
      end,
    })
    vim.api.nvim_buf_set_name(0, vim.fs.joinpath(vim.fn.getcwd(), "key-context.lua"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "    alpha beta", "second" })
    vim.bo.filetype = "lua"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]])
  input("v8l<F7>")
  wait([[_G.previews ~= nil]])
  eq(lua([[return previews.selection]]), "```lua\nalpha\n```")
  eq(lua([[return vim.api.nvim_get_mode().mode]]), "n")
  lua([[_G.previews = nil]])
  input("<F7>")
  wait([[_G.previews ~= nil]])
  eq(lua([[return previews.selection]]), vim.NIL)
  eq(lua([[return previews.file]]), "@key-context.lua")
  lua([[_G.previews = nil; require("agents").show(session.id)]])
  wait([[vim.api.nvim_get_mode().mode == "t"]])
  lua([[
    _G.notifications = {}
    _G.session_win = vim.api.nvim_get_current_win()
    vim.notify = function(message, level)
      table.insert(notifications, { message, level })
    end
  ]])
  input("<F7>")
  wait([[#notifications == 1]])
  eq(lua([[return notifications]]), {
    { "agents.nvim: send context from a non-session buffer", vim.log.levels.WARN },
  })
  eq(lua([[return previews]]), vim.NIL)
  eq(lua([[return vim.api.nvim_get_current_win()]]), lua([[return session_win]]))
  eq(lua([[return vim.api.nvim_get_current_buf()]]), lua([[return session.buf]]))
  eq(lua([[return vim.api.nvim_get_mode().mode]]), "t")
end

input_tests["actions preserves the visual selection when choosing send after picker focus changes"] = function()
  input("<F6>")
  wait([[vim.api.nvim_get_mode().mode == "n"]])
  lua([[
    require("agents").setup({
      tools = { cat = { cmd = { "cat" } } },
      keys = { { "<F7>", "actions" } },
      picker = function(spec)
        if spec.title == "Agents: Actions" then
          _G.actions_spec = spec
          vim.cmd.vnew()
          vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Picker buffer" })
        elseif spec.title == "Agents: Send Context" then
          _G.previews = {}
          for _, item in ipairs(spec.items) do
            _G.previews[item.text:match("^%S+")] = item.preview
          end
        end
      end,
    })
    _G.source_win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_name(0, vim.fs.joinpath(vim.fn.getcwd(), "actions-context.lua"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "    alpha beta", "second" })
    vim.bo.filetype = "lua"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]])
  input("v8l<F7>")
  wait([[_G.actions_spec ~= nil and vim.api.nvim_get_mode().mode == "n"]])
  eq(lua([[return vim.api.nvim_get_current_win() ~= source_win]]), true)
  lua([[
    for _, item in ipairs(actions_spec.items) do
      if item.data == "send" then
        actions_spec.actions[actions_spec.default](item)
        break
      end
    end
  ]])
  wait([[_G.previews ~= nil]])
  eq(lua([[return previews.selection]]), "```lua\nalpha\n```")
  eq(lua([[return previews.file]]), "@actions-context.lua")
end

input_tests["actions can hide a visually selected session without a source window"] = function()
  input("Terminal text<CR>")
  wait(
    [[table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n"):find("Terminal text", 1, true) ~= nil]]
  )
  input("<C-\\><C-n>")
  wait([[vim.api.nvim_get_mode().mode == "nt"]])
  lua([[
    vim.cmd.only()
    require("agents").setup({
      tools = { cat = { cmd = { "cat" } } },
      keys = { { "<F7>", "actions" } },
      picker = function(spec)
        _G.actions_spec = spec
      end,
    })
  ]])
  eq(lua([[return #vim.api.nvim_tabpage_list_wins(0)]]), 1)
  input("ggv<F7>")
  wait([[_G.actions_spec ~= nil and vim.api.nvim_get_mode().mode == "nt"]])
  eq(lua([[return actions_spec.title]]), "Agents: Actions")
  lua([[
    for _, item in ipairs(actions_spec.items) do
      if item.data == "hide" then
        actions_spec.actions[actions_spec.default](item)
        break
      end
    end
  ]])
  wait([[#vim.fn.win_findbuf(session.buf) == 0]])
  eq(lua([[return vim.fn.jobwait({ session.job }, 0)]]), { -1 })
end

return T
