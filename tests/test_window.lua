local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local window = require("agents.window")
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
local eq = test.expect.equality

T["layout opens each documented form"] = test.new_set({
  parametrize = {
    { "vsplit" },
    { "split" },
    { "botright 20vsplit" },
    { "tabnew" },
    { "current" },
    { "float" },
    { { width = 0.5, height = 0.5, border = "single", title = "Agent test", zindex = 70 } },
    {
      ---@param buf integer
      ---@return integer
      function(buf)
        return vim.api.nvim_open_win(
          buf,
          true,
          { relative = "editor", row = 1, col = 1, width = 30, height = 8 }
        )
      end,
    },
  },
}, {
  ---@param layout agents.Layout
  ["shows the session"] = function(layout)
    local session = H.new({ layout = layout })
    eq(vim.api.nvim_get_current_buf(), session.buf)
    eq(window.visible(session), true)
    eq(session.tab, vim.api.nvim_get_current_tabpage())
    eq(rawget(session, "win"), nil)
  end,
})

T["fractional float geometry is resolved once and config is not mutated"] = function()
  local opts = { width = 0.5, height = 0.5, border = "single", title = "Session", zindex = 70 }
  local original = vim.deepcopy(opts)
  local width, height = math.floor(vim.o.columns * 0.5), math.floor(vim.o.lines * 0.5)
  H.new({ layout = opts })
  local win = vim.api.nvim_get_current_win()
  local config = vim.api.nvim_win_get_config(win)
  eq({ config.width, config.height }, { width, height })
  eq(config.row, math.floor((vim.o.lines - height) / 2))
  eq(config.col, math.floor((vim.o.columns - width) / 2))
  eq(config.zindex, 70)
  eq(opts, original)
  vim.api.nvim_win_set_config(win, { width = 17 })
  vim.api.nvim_exec_autocmds("VimResized", {})
  eq(vim.api.nvim_win_get_width(win), 17)
end

T["float coordinates and cell dimensions pass through"] = function()
  H.new({ layout = { width = 12, height = 4, row = 0, col = 0, relative = "editor" } })
  local config = vim.api.nvim_win_get_config(0)
  eq({ config.width, config.height, config.row, config.col }, { 12, 4, 0, 0 })
end

T["show reuses an existing window in another tab"] = function()
  local session = H.new({ layout = "tabnew" })
  local win, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
  vim.cmd.tabprevious()
  agents.show(session.id, { layout = "float" })
  eq(vim.api.nvim_get_current_win(), win)
  eq(vim.api.nvim_get_current_tabpage(), tab)
  eq(vim.fn.win_findbuf(session.buf), { win })
end

T["hide closes a sole-window tab and keeps its job running"] = function()
  local session = H.new({ layout = "tabnew" })
  local tab = vim.api.nvim_get_current_tabpage()
  agents.hide(session.id)
  eq(vim.api.nvim_tabpage_is_valid(tab), false)
  eq(window.visible(session), false)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["hide uses the alternate buffer in the final window"] = function()
  local original = vim.api.nvim_get_current_buf()
  local session = H.new({ layout = "current" })
  agents.hide(session.id)
  eq(vim.api.nvim_get_current_buf(), original)
  eq(#vim.api.nvim_list_wins(), 1)
  eq(window.visible(session), false)
end

T["hide creates an empty buffer when no alternate survives"] = function()
  local original = vim.api.nvim_get_current_buf()
  local session = H.new({ layout = "current" })
  vim.api.nvim_buf_delete(original, { force = true })
  agents.hide(session.id)
  eq(vim.api.nvim_get_current_buf() ~= session.buf, true)
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
  eq(vim.bo.buftype, "")
end

T["two remaining agent windows"] = test.new_set({
  parametrize = { { "hide" }, { "close" } },
}, {
  ---@param first_action "hide"|"close"
  ["hiding the last window does not reopen the first agent"] = function(first_action)
    local first = H.new({ layout = "current" })
    local second = H.new({ layout = "vsplit" })
    eq(#vim.api.nvim_list_wins(), 2)
    eq(vim.fn.bufnr("#"), first.buf)

    agents[first_action](first.id)
    eq(#vim.api.nvim_list_wins(), 1)
    eq(vim.api.nvim_get_current_buf(), second.buf)
    agents.hide(second.id)

    eq(window.visible(first), false)
    eq(window.visible(second), false)
    eq(#vim.api.nvim_list_wins(), 1)
    eq(vim.bo.buftype, "")
    eq(vim.api.nvim_buf_get_name(0), "")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    eq(agents.current(), nil)
    eq(vim.fn.jobwait({ second.job }, 0), { -1 })
    if first_action == "hide" then
      eq(agents.sessions(), { first, second })
      eq(vim.fn.jobwait({ first.job }, 0), { -1 })
    else
      eq(agents.sessions(), { second })
      H.wait(function()
        return first.state == "exited"
      end)
    end
  end,
})

T["renamed terminal in the final window"] = test.new_set({
  parametrize = { { "hide" }, { "close" } },
}, {
  ---@param action "hide"|"close"
  ["leaves an empty buffer without restarting the terminal"] = function(action)
    local group = vim.api.nvim_create_augroup("AgentsRenamedTerminalTest", { clear = true })
    test.finally(function()
      vim.api.nvim_del_augroup_by_id(group)
    end)
    local starts = 0
    vim.api.nvim_create_autocmd("TermOpen", {
      group = group,
      callback = function(ev)
        starts = starts + 1
        vim.api.nvim_buf_set_name(ev.buf, "[Term] " .. ev.buf)
      end,
    })
    local session = H.new({ layout = "current" })
    -- Renaming leaves an unloaded alternate with the original term:// name.
    local alternate = vim.fn.bufnr("#")
    eq(vim.api.nvim_buf_is_valid(alternate), true)
    eq(vim.api.nvim_buf_is_loaded(alternate), false)
    eq(vim.api.nvim_buf_get_name(alternate):match("^term://") ~= nil, true)

    agents[action](session.id)
    if action == "close" then
      H.wait(function()
        return session.state == "exited" and not vim.api.nvim_buf_is_valid(session.buf)
      end)
      eq(agents.sessions(), {})
      eq(vim.fn.jobwait({ session.job }, 0)[1] ~= -1, true)
    else
      eq(agents.sessions(), { session })
      eq(vim.fn.jobwait({ session.job }, 0), { -1 })
      eq(window.visible(session), false)
    end
    eq(starts, 1)
    eq(#vim.api.nvim_list_wins(), 1)
    eq(vim.bo.buftype, "")
    eq(vim.api.nvim_buf_get_name(0), "")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    eq(agents.current(), nil)
  end,
})

T["hide removes every view of a session across tabs"] = function()
  local session = H.new()
  vim.cmd.split()
  vim.cmd.tabnew()
  vim.api.nvim_win_set_buf(0, session.buf)
  eq(#vim.fn.win_findbuf(session.buf), 3)
  agents.hide(session.id)
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["native buffer replacement hides a session without plugin involvement"] = function()
  local original = vim.api.nvim_get_current_buf()
  local session = H.new()
  vim.cmd.buffer(original)
  eq(window.visible(session), false)
  eq(agents.current(), nil)
  eq(agents.sessions(), { session })
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["TermOpen and filetype customizations are preserved"] = function()
  local group = vim.api.nvim_create_augroup("AgentsWindowTest", { clear = true })
  test.finally(function()
    vim.api.nvim_del_augroup_by_id(group)
  end)
  ---@type integer?
  local observed
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      observed = vim.b[ev.buf].agents_session
      vim.wo.number = true
      vim.wo.signcolumn = "yes:2"
      vim.wo.winfixwidth = true
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "agents_terminal",
    callback = function()
      vim.wo.foldcolumn = "3"
    end,
  })
  local session = H.new()
  eq(observed, session.id)
  eq(
    { vim.wo.number, vim.wo.signcolumn, vim.wo.winfixwidth, vim.wo.foldcolumn },
    { true, "yes:2", true, "3" }
  )
end

return T
