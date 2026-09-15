local test = require("mini.test")
---@type integer?
local channel
local init = vim.fn.fnamemodify("tests/minimal_init.lua", ":p")
---@type string?
local fixture_dir
local eq = test.expect.equality

-- Stdio RPC keeps these event-loop tests independent of local socket permissions.
---@param args string[]
local function start(args)
  local cmd = { vim.v.progpath, "--embed", "--headless", "--clean", "-n" }
  vim.list_extend(cmd, args)
  channel = vim.fn.jobstart(cmd, { rpc = true })
  assert(channel > 0, "Could not start child Neovim")
end

---The executed chunk determines the serialized RPC result's shape.
---@param code string
---@param args? any[]
---@return any
local function lua(code, args)
  return vim.rpcrequest(assert(channel), "nvim_exec_lua", code, args or {})
end

---@param code string
---@return any
local function get(code)
  return lua("return " .. code)
end

---@param keys string
local function input(keys)
  vim.rpcrequest(assert(channel), "nvim_input", keys)
end

local function stop()
  if channel then
    pcall(vim.rpcrequest, channel, "nvim_command", "qa!")
    if vim.fn.jobwait({ channel }, 1000)[1] == -1 then
      vim.fn.jobstop(channel)
      vim.fn.jobwait({ channel }, 1000)
    end
    channel = nil
  end
end

---@param insert_on_focus? boolean
local function setup(insert_on_focus)
  lua(
    [[require("gents").setup({
      insert_on_focus = ...,
      tools = { cat = { cmd = { "cat" } } },
    })]],
    { insert_on_focus or false }
  )
end

---@param expected string
local function mode(expected)
  local reached = vim.wait(2000, function()
    return get("vim.api.nvim_get_mode().mode") == expected
  end, 10)
  eq({ reached, get("vim.api.nvim_get_mode().mode") }, { true, expected })
end

local function spawn()
  lua([[_G.session = require("gents").new("cat")]])
  mode("t")
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      start({ "-u", init, "-i", "NONE" })
      setup()
    end,
    post_case = function()
      if not channel then
        return
      end
      local ok, err = pcall(
        lua,
        [[
        local gents = require("gents")
        local jobs = {}
        for _, session in ipairs(gents.sessions()) do
          jobs[#jobs + 1] = session.job
          gents.close(session.id)
        end
        if #jobs > 0 then
          vim.fn.jobwait(jobs, 2000)
        end
      ]]
      )
      stop()
      if fixture_dir then
        vim.fn.delete(fixture_dir, "rf")
        fixture_dir = nil
      end
      assert(ok, err)
    end,
  },
})

T["new enters terminal input after returning to the event loop"] = function()
  setup(true)
  spawn()
  eq(get("vim.fn.jobwait({ session.job }, 0)"), { -1 })
  input("gents input<CR>")
  eq(
    vim.wait(2000, function()
      return get([[table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")]]):find(
        "gents input",
        1,
        true
      ) ~= nil
    end, 10),
    true
  )
end

T["float resizing"] = test.new_set({ parametrize = { { "t" }, { "nt" }, { "n" }, { "i" } } }, {
  ---@param expected string
  ["preserves the current window, mode, buffer, and job"] = function(expected)
    lua([[
      _G.source_win = vim.api.nvim_get_current_win()
      _G.session = require("gents").new("cat", {
        layout = {
          width = function() return 0.5 end,
          height = function() return 0.5 end,
        },
      })
      _G.float_win = vim.api.nvim_get_current_win()
      _G.original_buf, _G.original_job = session.buf, session.job
    ]])
    mode("t")
    if expected == "nt" then
      input([[<C-\><C-n>]])
    elseif expected == "n" or expected == "i" then
      lua([[vim.api.nvim_set_current_win(source_win); vim.cmd.stopinsert()]])
      mode("n")
      if expected == "i" then
        input("i")
      end
    end
    mode(expected)
    local current = get("vim.api.nvim_get_current_win()")

    lua([[
      vim.o.columns, vim.o.lines = 100, 40
      vim.api.nvim_exec_autocmds("VimResized", {})
    ]])

    mode(expected)
    eq(get("vim.api.nvim_get_current_win()"), current)
    eq(get("vim.api.nvim_win_get_buf(float_win) == original_buf"), true)
    eq(get("session.buf == original_buf and session.job == original_job"), true)
    eq(get("vim.fn.jobwait({ session.job }, 0)"), { -1 })
    eq(get("vim.api.nvim_win_get_width(float_win)"), 50)
    eq(get("vim.api.nvim_win_get_height(float_win)"), 20)
  end,
})

T["explicit show enters terminal input for hidden and visible sessions"] = function()
  setup(true)
  spawn()
  input([[<C-\><C-n>]])
  mode("nt")
  lua([[require("gents").hide(session.id)]])
  mode("n")
  lua([[require("gents").show(session.id)]])
  mode("t")

  input([[<C-\><C-n>]])
  mode("nt")
  lua([[require("gents").show(session.id)]])
  mode("t")
end

T["focus mappings leave terminal input and refocus the visible session"] = function()
  lua([[
    _G.source_win = vim.api.nvim_get_current_win()
    vim.keymap.set({ "n", "t" }, "<F5>", function()
      require("gents").focus()
    end)
  ]])
  spawn()
  lua([[_G.terminal_win = vim.api.nvim_get_current_win()]])

  input("<F5>")
  mode("n")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  eq(get("vim.api.nvim_win_get_buf(terminal_win) == session.buf"), true)
  eq(get("vim.fn.jobwait({ session.job }, 0)"), { -1 })

  input("<F5>")
  mode("t")
  eq(get("vim.api.nvim_get_current_win() == terminal_win"), true)
  eq(get("#require('gents').sessions()"), 1)
end

T["focus returns to a previous terminal window in normal mode"] = function()
  spawn()
  lua([[
    _G.previous = session
    _G.previous_win = vim.api.nvim_get_current_win()
  ]])
  spawn()

  lua([[require("gents").focus()]])

  mode("nt")
  eq(get("vim.api.nvim_get_current_win() == previous_win"), true)
  eq(get("require('gents').current() == previous"), true)
  eq(get("require('gents.window').visible(session)"), true)
  eq(get("vim.fn.jobwait({ previous.job, session.job }, 0)"), { -1, -1 })
end

T["native window reentry preserves terminal normal mode"] = function()
  lua([[_G.source_win = vim.api.nvim_get_current_win()]])
  spawn()
  lua([[_G.terminal_win = vim.api.nvim_get_current_win()]])
  input([[<C-\><C-n>]])
  mode("nt")
  input("<C-w>p")
  mode("n")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  input("<C-w>p")
  mode("nt")
  eq(get("vim.api.nvim_get_current_win() == terminal_win"), true)
end

T["terminal navigation resumes input when returning to a session"] = function()
  lua([[
    vim.o.splitright = true
    _G.source_win = vim.api.nvim_get_current_win()
    vim.keymap.set("t", "<C-w>h", "<C-\\><C-n><C-w>h")
  ]])
  spawn()
  lua([[_G.terminal_win = vim.api.nvim_get_current_win()]])

  input("<C-w>h")
  mode("n")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  input("<C-w>l")
  mode("t")
  eq(get("vim.api.nvim_get_current_win() == terminal_win"), true)
end

T["same-window buffer reentry restores input only when left during input"] = function()
  lua([[
    require("gents").setup({ layout = "current", tools = { cat = { cmd = { "cat" } } } })
    _G.source_buf = vim.api.nvim_get_current_buf()
    vim.keymap.set("t", "<F6>", "<C-\\><C-n><C-^>")
  ]])
  spawn()

  input("<F6>")
  mode("n")
  eq(get("vim.api.nvim_get_current_buf() == source_buf"), true)
  input("<C-^>")
  mode("t")
  eq(get("vim.api.nvim_get_current_buf() == session.buf"), true)

  input([[<C-\><C-n>]])
  mode("nt")
  input("<C-^>")
  mode("n")
  input("<C-^>")
  mode("nt")
  eq(get("vim.api.nvim_get_current_buf() == session.buf"), true)
end

T["sending focuses terminal input once without stealing focus during queued delivery"] = function()
  lua([[
    _G.source_win = vim.api.nvim_get_current_win()
    _G.sent = 0
    vim.api.nvim_create_autocmd("User", {
      pattern = "GentsSend",
      callback = function()
        sent = sent + 1
      end,
    })
    require("gents").setup({
      tools = { cat = { cmd = { "sh", "-c", "printf '1\\n2\\n3\\n4\\n5\\n6\\n'; exec cat" } } },
    })
  ]])
  spawn()
  lua([[require("gents").hide(session.id)]])
  mode("n")

  lua([[require("gents").send({ { text = "first send" } }, { target = session.id })]])
  mode("t")
  eq(get("vim.api.nvim_get_current_buf() == session.buf"), true)
  lua([[require("gents").focus()]])
  mode("n")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  eq(
    vim.wait(2000, function()
      return get("sent") == 1
    end, 10),
    true
  )
  mode("n")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)

  lua([[require("gents").send({ { text = "second send" } }, { target = session.id })]])
  mode("t")
  eq(get("vim.api.nvim_get_current_buf() == session.buf"), true)
end

T["sending without focus preserves editor normal mode when reopening a session"] = function()
  lua([[
    _G.source_win = vim.api.nvim_get_current_win()
    vim.keymap.set("n", "<F7>", function()
      require("gents").send({ { text = "test" } }, { target = session.id, focus = false })
    end)
  ]])
  spawn()
  lua([[require("gents").hide(session.id)]])
  mode("n")

  input("<F7>")
  mode("n")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  eq(get("require('gents.window').visible(session)"), true)
end

T["send target current placement"] = test.new_set({
  parametrize = { { true, "t" }, { false, "t" }, { true, "nt" }, { false, "nt" } },
}, {
  ---@param focus boolean
  ---@param previous_mode string
  ["enters terminal input regardless of focus or previous terminal mode"] = function(
    focus,
    previous_mode
  )
    lua([[_G.source_win = vim.api.nvim_get_current_win()]])
    spawn()
    if previous_mode == "nt" then
      input([[<C-\><C-n>]])
      mode("nt")
    end
    lua([[
      _G.selected = session
      require("gents").hide(selected.id)
    ]])
    mode("n")
    spawn()
    lua([[
      require("gents").hide(session.id)
      require("gents").setup({
        picker = function(spec)
          _G.picker = spec
        end,
      })
    ]])
    mode("n")
    lua([[require("gents").send({ { text = "test" } }, { focus = ... })]], { focus })
    eq(get("picker.title"), "Gents: Sessions")
    lua([[
      for _, item in ipairs(picker.items) do
        if item.data == selected then
          picker.actions.current(item)
          break
        end
      end
    ]])
    mode("t")
    eq(get("vim.api.nvim_get_current_win() == source_win"), true)
    eq(get("vim.api.nvim_get_current_buf() == selected.buf"), true)
  end,
})

T["sending to a new session"] = test.new_set({
  parametrize = { { true, false }, { false, false }, { true, true }, { false, true } },
}, {
  ---@param focus boolean
  ---@param enabled boolean
  ["respects terminal input focus after choosing a tool"] = function(focus, enabled)
    setup(enabled)
    lua(
      [[
      _G.source_win = vim.api.nvim_get_current_win()
      require("gents.config").get().picker = function(spec)
        _G.picker = spec
      end
      require("gents").send({ { text = "test" } }, { focus = ... })
    ]],
      { focus }
    )
    eq(get("picker.title"), "Gents: New Session")
    lua([[
      for _, item in ipairs(picker.items) do
        if item.data.name == "cat" then
          picker.actions[picker.default](item)
          break
        end
      end
      _G.session = assert(require("gents").sessions()[1])
    ]])
    mode(focus and "t" or "n")
    eq(get("vim.api.nvim_get_current_win() == source_win"), not focus)
    eq(get("require('gents.window').visible(session)"), true)
  end,
})

T["sending without focus preserves editor insert mode when reopening a session"] = function()
  lua([[
    _G.source_win = vim.api.nvim_get_current_win()
    vim.keymap.set("i", "<F7>", function()
      require("gents").send({ { text = "test" } }, { target = session.id, focus = false })
    end)
  ]])
  spawn()
  lua([[require("gents").hide(session.id)]])
  mode("n")
  input("i")
  mode("i")

  input("<F7>")
  mode("i")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  eq(get("require('gents.window').visible(session)"), true)
end

T["window reentry does not resume input after the session exits"] = function()
  lua([[
    vim.o.splitright = true
    vim.keymap.set("t", "<C-w>h", "<C-\\><C-n><C-w>h")
  ]])
  spawn()

  input("<C-w>h")
  mode("n")
  lua([[vim.fn.jobstop(session.job)]])
  eq(
    vim.wait(2000, function()
      return get([[session.state == "exited"]])
    end, 10),
    true
  )
  input("<C-w>l")
  mode("nt")
  eq(get("vim.api.nvim_get_current_buf() == session.buf"), true)
end

T["window reentry does not change ordinary terminal behavior"] = function()
  setup(true)
  lua([[
    vim.o.splitright = true
    vim.keymap.set("t", "<C-w>h", "<C-\\><C-n><C-w>h")
    vim.cmd.vsplit()
    vim.cmd.enew()
    _G.terminal_win = vim.api.nvim_get_current_win()
    _G.terminal_job = vim.fn.jobstart({ "cat" }, { term = true })
    vim.cmd.startinsert()
  ]])
  mode("t")

  input("<C-w>h")
  mode("n")
  input("<C-w>l")
  mode("nt")
  eq(get("vim.api.nvim_get_current_win() == terminal_win"), true)
  lua([[vim.fn.jobstop(terminal_job); vim.fn.jobwait({ terminal_job }, 2000)]])
end

T["loading setup and new install no global or terminal buffer keymaps"] = function()
  stop()
  start({ "-u", init, "-i", "NONE", "--noplugin" })
  lua([[
    _G.modes = { "n", "x", "s", "o", "i", "c", "t" }
    _G.before, _G.terminal_maps = {}, {}
    _G.buffer_maps = function(buf, mode)
      local maps = vim.api.nvim_buf_get_keymap(buf, mode)
      for _, map in ipairs(maps) do
        map.buf, map.buffer = nil, nil
        map.callback = type(map.callback)
      end
      return maps
    end
    local job = vim.fn.jobstart({ "cat" }, { term = true })
    for _, mode in ipairs(modes) do
      before[mode] = vim.api.nvim_get_keymap(mode)
      terminal_maps[mode] = buffer_maps(0, mode)
    end
    vim.fn.jobstop(job)
    vim.fn.jobwait({ job }, 2000)
    vim.api.nvim_buf_delete(0, { force = true })
  ]])
  lua([[vim.cmd("runtime plugin/gents.lua")]])
  setup()
  spawn()
  eq(
    get([[(function()
    for _, mode in ipairs(modes) do
      if not vim.deep_equal(before[mode], vim.api.nvim_get_keymap(mode)) then
        return "Global mappings changed in mode " .. mode
      end
      if not vim.deep_equal(terminal_maps[mode], buffer_maps(session.buf, mode)) then
        return "Terminal mappings changed in mode " .. mode
      end
    end
    return true
  end)()]]),
    true
  )
end

T["TermOpen and a real ftplugin retain their window customizations after current placement"] = function()
  fixture_dir = vim.fn.tempname()
  vim.fn.mkdir(fixture_dir .. "/ftplugin", "p")
  vim.fn.writefile({
    "vim.wo.relativenumber = true",
    "vim.wo.signcolumn = 'yes:3'",
    "vim.wo.wrap = false",
    "vim.b.gents_test_ftplugin = true",
  }, fixture_dir .. "/ftplugin/gents_terminal.lua")
  lua("vim.opt.runtimepath:append(...)", { fixture_dir })
  lua([[vim.cmd("filetype plugin on")]])
  lua([[
    _G.source_win, _G.source_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    _G.window_options = function()
      return {
        vim.wo.number, vim.wo.foldcolumn, vim.wo.winfixwidth,
        vim.wo.relativenumber, vim.wo.signcolumn, vim.wo.wrap,
      }
    end
    vim.wo.number, vim.wo.relativenumber = true, false
    vim.wo.foldcolumn, vim.wo.signcolumn = "1", "yes:1"
    vim.wo.winfixwidth, vim.wo.wrap = false, true
    _G.source_options = window_options()
    vim.api.nvim_create_autocmd("TermOpen", { callback = function(ev)
      _G.termopen_session = vim.b[ev.buf].gents_session
      vim.wo.number = true
      vim.wo.foldcolumn = "3"
      vim.wo.winfixwidth = true
    end })
  ]])
  spawn()
  eq(get("termopen_session == session.id"), true)
  eq(get("vim.b.gents_test_ftplugin"), true)
  local expected = { true, "3", true, true, "yes:3", false }
  eq(get("window_options()"), expected)
  lua([[_G.terminal_win = vim.api.nvim_get_current_win()]])

  input([[<C-\><C-n>]])
  mode("nt")
  lua([[vim.api.nvim_set_current_win(source_win)]])
  mode("n")
  eq(get("window_options()"), get("source_options"))
  lua([[require("gents").show(session.id, { layout = "current" })]])
  mode("t")
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
  -- winfixwidth belongs to a window; display options belong to its buffer view.
  eq(get("window_options()"), { true, "3", false, true, "yes:3", false })
  eq(get("vim.wo[terminal_win].winfixwidth"), true)
  eq(get("vim.b.gents_test_ftplugin"), true)

  input([[<C-\><C-n>]])
  mode("nt")
  lua([[vim.api.nvim_set_current_buf(source_buf)]])
  mode("n")
  eq(get("window_options()"), get("source_options"))
  eq(get("#require('gents').sessions()"), 1)
  eq(get("vim.fn.jobwait({ session.job }, 0)"), { -1 })
end

local focus_option = test.new_set({ parametrize = { { false }, { true } } })
T["insert on focus"] = focus_option

focus_option["native navigation"] = test.new_set({
  parametrize = { { "window" }, { "buffer" }, { "tab" }, { "shared buffer" } },
}, {
  ---@param enabled boolean
  ---@param route string
  ["respects the option after inspecting output"] = function(enabled, route)
    setup(enabled)
    lua([[_G.source_win = vim.api.nvim_get_current_win()]])
    spawn()
    if route == "shared buffer" then
      lua([[vim.cmd.split()]])
      mode("t")
    end
    input([[<C-\><C-n>]])
    mode("nt")
    input("gg")
    mode("nt")
    lua([[_G.terminal_win = vim.api.nvim_get_current_win()]])

    if route == "buffer" then
      lua([[vim.cmd.enew()]])
    elseif route == "tab" then
      lua([[vim.cmd.tabnew()]])
    else
      input("<C-w>p")
    end
    mode(route == "shared buffer" and (enabled and "t" or "nt") or "n")
    if route == "shared buffer" and enabled then
      input([[<C-\><C-n>]])
      mode("nt")
    end

    if route == "buffer" then
      input("<C-^>")
    elseif route == "tab" then
      input("gT")
    else
      input("<C-w>p")
    end
    mode(enabled and "t" or "nt")
    eq(get("vim.api.nvim_get_current_win() == terminal_win"), true)
    eq(get("require('gents').current() == session"), true)
    eq(get("vim.fn.jobwait({ session.job }, 0)"), { -1 })
  end,
})

focus_option["previous window"] = test.new_set({
  parametrize = { { "live" }, { "exited" }, { "editor" }, { "terminal" } },
}, {
  ---@param enabled boolean
  ---@param destination string
  ["focus uses the destination session state"] = function(enabled, destination)
    setup(enabled)
    if destination == "live" or destination == "exited" then
      spawn()
      if destination == "exited" then
        lua([[vim.fn.jobstop(session.job)]])
        eq(
          vim.wait(2000, function()
            return get([[session.state == "exited"]])
          end, 10),
          true
        )
      end
    elseif destination == "terminal" then
      lua([[_G.ordinary_job = vim.fn.jobstart({ "cat" }, { term = true })]])
    end
    lua([[_G.previous_win = vim.api.nvim_get_current_win()]])
    spawn()
    lua([[
      vim.keymap.set("t", "<F5>", function() require("gents").focus() end)
    ]])
    input("<F5>")
    mode(destination == "editor" and "n" or (enabled and destination == "live" and "t" or "nt"))
    eq(get("vim.api.nvim_get_current_win() == previous_win"), true)
    eq(get("require('gents.window').visible(session)"), true)
    if destination == "terminal" then
      lua([[vim.fn.jobstop(ordinary_job); vim.fn.jobwait({ ordinary_job }, 2000)]])
    end
  end,
})

focus_option["background send"] = test.new_set({ parametrize = { { "n" }, { "i" } } }, {
  ---@param enabled boolean
  ---@param source_mode string
  ["preserves editor mode after reopening from terminal normal mode"] = function(
    enabled,
    source_mode
  )
    setup(enabled)
    lua([[_G.source_win = vim.api.nvim_get_current_win()]])
    spawn()
    input([[<C-\><C-n>]])
    mode("nt")
    lua([[require("gents").hide(session.id)]])
    mode("n")
    lua([[
      vim.keymap.set({ "n", "i" }, "<F7>", function()
        require("gents").send({ { text = "test" } }, { target = session.id, focus = false })
      end)
    ]])
    if source_mode == "i" then
      input("i")
      mode("i")
    end
    input("<F7>")
    mode(source_mode)
    eq(get("vim.api.nvim_get_current_win() == source_win"), true)
    eq(get("require('gents.window').visible(session)"), true)
  end,
})

---@param enabled boolean
focus_option["exited sessions stay in normal mode on native reentry"] = function(enabled)
  setup(enabled)
  spawn()
  lua([[
    _G.terminal_win = vim.api.nvim_get_current_win()
    require("gents").focus()
    vim.fn.jobstop(session.job)
  ]])
  mode("n")
  eq(
    vim.wait(2000, function()
      return get([[session.state == "exited"]])
    end, 10),
    true
  )
  input("<C-w>p")
  mode("nt")
  eq(get("vim.api.nvim_get_current_win() == terminal_win"), true)
end

---@param enabled boolean
focus_option["failed launches leave no pending input or session"] = function(enabled)
  setup(enabled)
  lua([[
    _G.started = pcall(require("gents").new, "cat", { cmd = { vim.fn.tempname() } })
  ]])
  mode("n")
  eq(get("started"), false)
  eq(get("#require('gents').sessions()"), 0)
  eq(get("vim.bo.buftype"), "")
end

---@param enabled boolean
focus_option["picker selection and current-window sends enter input"] = function(enabled)
  setup(enabled)
  lua([[_G.source_win = vim.api.nvim_get_current_win()]])
  spawn()
  input([[<C-\><C-n>]])
  mode("nt")
  lua([[
    require("gents").hide(session.id)
    require("gents.config").get().picker = function(spec) _G.picker = spec end
    require("gents").pick()
  ]])
  mode("n")
  eq(get("picker.title"), "Gents: Sessions")
  lua([[picker.actions[picker.default](picker.items[1])]])
  mode("t")
  eq(get("require('gents').current() == session"), true)

  input([[<C-\><C-n>]])
  mode("nt")
  lua([[
    require("gents").hide(session.id)
    require("gents.config").get().layout = "current"
    require("gents").send({ { text = "test" } }, { target = session.id, focus = false })
  ]])
  mode("t")
  eq(get("require('gents').current() == session"), true)
  eq(get("vim.api.nvim_get_current_win() == source_win"), true)
end

T["setup changes affect existing sessions on their next reentry"] = function()
  spawn()
  input([[<C-\><C-n>]])
  mode("nt")
  setup(true)
  mode("nt")
  input("<C-w>p")
  mode("n")
  input("<C-w>p")
  mode("t")
  input([[<C-\><C-n>]])
  mode("nt")
  setup(false)
  mode("nt")
  input("<C-w>p")
  mode("n")
  input("<C-w>p")
  mode("nt")
end

return T
