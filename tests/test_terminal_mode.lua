local test = require("mini.test")
local channel
local init = vim.fn.fnamemodify("tests/minimal_init.lua", ":p")
local fixture_dir
local eq = test.expect.equality

-- Stdio RPC keeps these event-loop tests independent of local socket permissions.
local function start(args)
  local cmd = { vim.v.progpath, "--embed", "--headless", "--clean", "-n" }
  vim.list_extend(cmd, args)
  channel = vim.fn.jobstart(cmd, { rpc = true })
  assert(channel > 0, "Could not start child Neovim")
end

local function lua(code, args)
  return vim.rpcrequest(channel, "nvim_exec_lua", code, args or {})
end

local function get(code)
  return lua("return " .. code)
end

local function input(keys)
  return vim.rpcrequest(channel, "nvim_input", keys)
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

local function setup()
  lua([[require("agents").setup({ tools = { cat = { cmd = { "cat" } } } })]])
end

local function mode(expected)
  local reached = vim.wait(2000, function()
    return get("vim.api.nvim_get_mode().mode") == expected
  end, 10)
  eq({ reached, get("vim.api.nvim_get_mode().mode") }, { true, expected })
end

local function spawn()
  lua([[_G.session = require("agents").new("cat")]])
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
        local agents = require("agents")
        local jobs = {}
        for _, session in ipairs(agents.sessions()) do
          jobs[#jobs + 1] = session.job
          agents.close(session.id)
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
  spawn()
  eq(get("vim.fn.jobwait({ session.job }, 0)"), { -1 })
  input("agents input<CR>")
  eq(
    vim.wait(2000, function()
      return get([[table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")]]):find(
        "agents input",
        1,
        true
      ) ~= nil
    end, 10),
    true
  )
end

T["explicit show enters terminal input for hidden and visible sessions"] = function()
  spawn()
  input([[<C-\><C-n>]])
  mode("nt")
  lua([[require("agents").hide(session.id)]])
  mode("n")
  lua([[require("agents").show(session.id)]])
  mode("t")

  input([[<C-\><C-n>]])
  mode("nt")
  lua([[require("agents").show(session.id)]])
  mode("t")
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
  lua([[vim.cmd("runtime plugin/agents.lua")]])
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

T["TermOpen and a real ftplugin retain their window customizations"] = function()
  fixture_dir = vim.fn.tempname()
  vim.fn.mkdir(fixture_dir .. "/ftplugin", "p")
  vim.fn.writefile({
    "vim.wo.relativenumber = true",
    "vim.wo.signcolumn = 'yes:3'",
    "vim.wo.wrap = false",
    "vim.b.agents_test_ftplugin = true",
  }, fixture_dir .. "/ftplugin/agents_terminal.lua")
  lua("vim.opt.runtimepath:append(...)", { fixture_dir })
  lua([[vim.cmd("filetype plugin on")]])
  lua([[
    vim.api.nvim_create_autocmd("TermOpen", { callback = function(ev)
      _G.termopen_session = vim.b[ev.buf].agents_session
      vim.wo.number = true
      vim.wo.foldcolumn = "3"
      vim.wo.winfixwidth = true
    end })
  ]])
  spawn()
  eq(get("termopen_session == session.id"), true)
  eq(get("vim.b.agents_test_ftplugin"), true)
  eq(
    get([[{
    vim.wo.number, vim.wo.foldcolumn, vim.wo.winfixwidth,
    vim.wo.relativenumber, vim.wo.signcolumn, vim.wo.wrap,
  }]]),
    { true, "3", true, true, "yes:3", false }
  )
end

return T
