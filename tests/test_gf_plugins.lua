local test = require("mini.test")
local eq = test.expect.equality

---@type { [1]: string, [2]: string, [3]: boolean }[]
local cases = {}
for name, variable in pairs({
  fugitive = "FUGITIVE_DIR",
  diffview = "DIFFVIEW_DIR",
  snacks = "SNACKS_DIR",
  canola = "CANOLA_DIR",
}) do
  local directory = os.getenv(variable)
  if directory and vim.uv.fs_stat(directory) then
    for _, first in ipairs({ true, false }) do
      cases[#cases + 1] = { name, directory, first }
    end
  end
end
table.sort(cases, function(a, b)
  return a[1] < b[1] or (a[1] == b[1] and a[3] and not b[3])
end)

local T = test.new_set({ parametrize = cases })
if #cases == 0 then
  return T
end

---@param plugin string
---@param directory string
---@param plugin_first boolean
T["real plugin gf delegation in either load order"] = function(plugin, directory, plugin_first)
  local root = vim.fn.getcwd()
  if plugin == "fugitive" or plugin == "diffview" then
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/lua/gents", "p")
    local file = root .. "/lua/gents/init.lua"
    vim.fn.writefile({ "return {}" }, file)
    for _, args in ipairs({
      { "init", "--quiet", "--template=" },
      { "add", "lua/gents/init.lua" },
      {
        "-c",
        "user.name=Gents test",
        "-c",
        "user.email=gents@example.test",
        "-c",
        "core.hooksPath=/dev/null",
        "commit",
        "--quiet",
        "--no-gpg-sign",
        "-m",
        "fixture",
      },
    }) do
      local cmd = { "git", "-C", root }
      vim.list_extend(cmd, args)
      local result = vim.system(cmd, { text = true }):wait()
      assert(result.code == 0, result.stderr)
    end
    vim.fn.writefile({ "return { changed = true }" }, file)
    test.finally(function()
      vim.fn.delete(root, "rf")
    end)
  end
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
      if _G.gents_test_terminal then _G.gents_test_terminal:close() end
      require("gents").setup()
      if package.loaded["diffview.lib"] then require("diffview.lib").close() end
    ]],
      {}
    )
    pcall(vim.rpcrequest, channel, "nvim_command", "qa!")
    if vim.fn.jobwait({ channel }, 1000)[1] == -1 then
      vim.fn.jobstop(channel)
      vim.fn.jobwait({ channel }, 1000)
    end
  end)
  vim.rpcrequest(
    channel,
    "nvim_exec_lua",
    [[
    local root, plugin, directory, plugin_first = ...
    vim.cmd.cd(root)
    _G.gents_test_plugin = plugin
    local function enable() require("gents").setup({ extend_gf = true }) end
    if not plugin_first then enable() end
    vim.opt.runtimepath:prepend(directory)
    vim.cmd("filetype plugin on")
    if plugin == "fugitive" then
      vim.cmd.runtime("plugin/fugitive.vim")
      vim.cmd.edit(root .. "/lua/gents/init.lua")
      vim.cmd.Git()
      local found = false
      for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        local column = line:find("lua/gents/init.lua", 1, true)
        if column then
          vim.api.nvim_win_set_cursor(0, { row, column - 1 })
          found = true
          break
        end
      end
      assert(found, "Expected changed init.lua in Fugitive's status")
      _G.gents_test_expected = root .. "/lua/gents/init.lua"
    elseif plugin == "diffview" then
      vim.cmd.runtime("plugin/diffview.lua")
      require("diffview").setup()
      vim.cmd("DiffviewOpen -- lua/gents/init.lua")
      _G.gents_test_expected = root .. "/lua/gents/init.lua"
    elseif plugin == "snacks" then
      require("snacks").setup()
      _G.gents_test_terminal = Snacks.terminal.open({"sh", "-c", "printf 'README.md\\n'; exec cat"}, {
        cwd = root, interactive = false, win = {position = "right"},
      })
      assert(vim.wait(2000, function()
        for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
          local column = line:find("README.md", 1, true)
          if column then
            vim.api.nvim_win_set_cursor(0, {row, column - 1})
            return true
          end
        end
        return false
      end))
      _G.gents_test_expected = root .. "/README.md"
    elseif plugin == "canola" then
      -- Exercise real SSH read/gf callbacks with a local fake transport.
      -- This test does not depend on an SSH host or credentials.
      require("oil.config").setup()
      local shell = require("oil.shell")
      shell.run = function(cmd, callback)
        assert(cmd[1] == "scp", "Unexpected remote transport")
        vim.fn.writefile({"other.lua"}, cmd[#cmd])
        vim.schedule(function() callback(nil) end)
      end
      local util = require("oil.util")
      util.adapter_list_all = function(_, _, _, callback)
        callback(nil, {{1, "other.lua", "file"}})
      end
      vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "oil-ssh://*",
        callback = function(ev)
          require("oil.adapters.ssh").read_file(ev.buf)
        end,
      })
      vim.api.nvim_buf_set_name(0, "oil-ssh://example.test//project/main.lua")
      require("oil.adapters.ssh").read_file(vim.api.nvim_get_current_buf())
      assert(vim.wait(2000, function()
        return vim.api.nvim_get_current_line() == "other.lua"
      end))
      vim.api.nvim_win_set_cursor(0, {1, 0})
      _G.gents_test_expected = "oil-ssh://example.test//project/other.lua"
    end
    if plugin == "diffview" then return end
    vim.cmd.stopinsert()
    if plugin_first then enable() end
    assert(vim.wait(2000, function()
      return vim.fn.maparg("gf", "n", false, true).desc
        == "Gents: follow conversation reference or original gf"
    end), "Expected the Gents wrapper after plugin initialization")
  ]],
    { root, plugin, directory, plugin_first }
  )
  if plugin == "diffview" then
    -- Let asynchronous Git work finish between RPC calls. Waiting inside the
    -- startup RPC can block Diffview's scheduled panel initialization.
    assert(
      vim.wait(4000, function()
        return vim.rpcrequest(
          channel,
          "nvim_exec_lua",
          [[
        local view = require("diffview.lib").get_current_view()
        if not view or not view.panel or not view.panel.cur_file then return false end
        view.panel:focus()
        view.panel:highlight_cur_file()
        return view:infer_cur_file() ~= nil
      ]],
          {}
        ) == true
      end),
      "Expected a rendered file row under the panel cursor"
    )
    vim.rpcrequest(
      channel,
      "nvim_exec_lua",
      [[
      vim.cmd.stopinsert()
      if ... then require("gents").setup({extend_gf=true}) end
    ]],
      { plugin_first }
    )
    assert(
      vim.wait(2000, function()
        return vim.rpcrequest(
          channel,
          "nvim_exec_lua",
          [[
        return vim.fn.maparg("gf", "n", false, true).desc
          == "Gents: follow conversation reference or original gf"
      ]],
          {}
        ) == true
      end),
      "Expected the Gents wrapper in the Diffview panel"
    )
  end
  vim.rpcrequest(channel, "nvim_input", "gf")
  local reached = vim.wait(4000, function()
    return vim.rpcrequest(
      channel,
      "nvim_exec_lua",
      [[
      local actual = vim.api.nvim_buf_get_name(0)
      if gents_test_plugin == "canola" then return actual == gents_test_expected end
      return vim.uv.fs_realpath(actual) == vim.uv.fs_realpath(gents_test_expected)
    ]],
      {}
    ) == true
  end, 10)
  if not reached then
    local state = vim.rpcrequest(
      channel,
      "nvim_exec_lua",
      [[
      return { vim.api.nvim_buf_get_name(0), vim.v.errmsg,
        vim.api.nvim_exec2("messages", {output=true}).output }
    ]],
      {}
    )
    error(vim.inspect(state))
  end
end

return T
