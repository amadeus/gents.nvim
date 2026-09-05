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
      mode = { "n", "x" },
    },
  })
  local session = helpers.new()
  eq(mapping("n", "<F6>"), nil)
  eq(mapping("x", "<F6>"), nil)
  eq(type(assert(mapping("t", "<F6>", session.buf)).callback), "function")
  eq(mapping("t", "<F7>", session.buf), nil)
  assert(assert(mapping("n", "<F7>")).callback)()
  assert(assert(mapping("x", "<F7>")).callback)()
  eq(invoked, 2)
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
    { { "<F6>", "toggle", mode = "i" } },
    { { "<F6>", "toggle", mode = { "n", "i" } } },
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
  eq(title, "Agents: send context")
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
  input("<F7>")
  wait([[_G.previews ~= nil]])
  eq(lua([[return previews.file]]), "@key-context.lua")
end

return T
