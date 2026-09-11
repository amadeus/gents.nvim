local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local window = require("gents.window")
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
local eq = test.expect.equality

---@param callback fun(message: string, level?: integer)
local function set_notify(callback)
  vim.notify = callback
end

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
      ---@return integer
      function()
        return vim.api.nvim_open_win(
          0,
          true,
          { relative = "editor", row = 1, col = 1, width = 30, height = 8 }
        )
      end,
    },
  },
}, {
  ---@param layout gents.Layout
  ["shows the session"] = function(layout)
    local session = H.new({ layout = layout })
    eq(vim.api.nvim_get_current_buf(), session.buf)
    eq(window.visible(session), true)
    eq(session.tab, vim.api.nvim_get_current_tabpage())
    eq(rawget(session, "win"), nil)
  end,
})

T["new terminal window options"] = test.new_set({
  parametrize = { { "vsplit" }, { "current" }, { "tabnew" }, { "float" } },
}, {
  ---@param layout gents.Layout
  ["survive placement in the originating editor window"] = function(layout)
    local source_win, source_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local number, relativenumber = vim.wo.number, vim.wo.relativenumber
    test.finally(function()
      if vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_win_call(source_win, function()
          vim.wo.number, vim.wo.relativenumber = number, relativenumber
        end)
      end
    end)
    vim.wo.number, vim.wo.relativenumber = true, true

    local session = H.new({ layout = layout })
    local buf, job = session.buf, session.job
    eq({ vim.wo.number, vim.wo.relativenumber }, { false, false })
    vim.api.nvim_set_current_win(source_win)
    vim.api.nvim_win_set_buf(source_win, source_buf)
    eq({ vim.wo.number, vim.wo.relativenumber }, { true, true })

    gents.show(session.id, { layout = "current" })
    eq(vim.api.nvim_get_current_win(), source_win)
    eq(vim.api.nvim_get_current_buf(), buf)
    eq({ vim.wo.number, vim.wo.relativenumber }, { false, false })
    eq({ session.buf, session.job }, { buf, job })
    eq(gents.sessions(), { session })
    eq(vim.fn.jobwait({ job }, 0), { -1 })

    vim.api.nvim_win_set_buf(source_win, source_buf)
    eq({ vim.wo.number, vim.wo.relativenumber }, { true, true })
  end,
})

T["custom layouts choose the destination before a session buffer exists"] = function()
  local source_win = vim.api.nvim_get_current_win()
  local buffers = vim.api.nvim_list_bufs()
  ---@type integer?
  local destination
  local session = H.new({
    layout = function()
      eq(vim.api.nvim_list_bufs(), buffers)
      eq(gents.sessions(), {})
      vim.cmd.vsplit()
      destination = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(source_win)
      return assert(destination)
    end,
  })
  eq(vim.api.nvim_get_current_win(), destination)
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_win_get_buf(source_win) ~= session.buf, true)
end

---@param columns integer
---@param lines integer
local function resize_editor(columns, lines)
  vim.o.columns, vim.o.lines = columns, lines
  vim.api.nvim_exec_autocmds("VimResized", {})
end

local function restore_editor_size()
  local columns, lines = vim.o.columns, vim.o.lines
  test.finally(function()
    resize_editor(columns, lines)
  end)
end

T["fractional floats resize and recenter without mutating their config"] = function()
  restore_editor_size()
  resize_editor(80, 40)
  local opts = { width = 0.5, height = 0.5, border = "single", title = "Session", zindex = 70 }
  local original = vim.deepcopy(opts)
  H.new({ layout = opts })
  local win = vim.api.nvim_get_current_win()
  local config = vim.api.nvim_win_get_config(win)
  eq({ config.width, config.height, config.row, config.col }, { 40, 20, 10, 20 })
  eq(config.zindex, 70)
  eq(opts, original)

  vim.api.nvim_win_set_config(
    win,
    { relative = "editor", width = 17, row = 1.5, col = 2.5, title = "Native title", zindex = 90 }
  )
  local title = vim.api.nvim_win_get_config(win).title
  resize_editor(120, 60)
  config = vim.api.nvim_win_get_config(win)
  eq({ config.width, config.height, config.row, config.col }, { 60, 30, 15, 30 })
  eq({ config.title, config.zindex }, { title, 90 })
  eq(opts, original)
end

T["float coordinates and cell dimensions pass through"] = function()
  H.new({ layout = { width = 12, height = 4, row = 0, col = 0, relative = "editor" } })
  local config = vim.api.nvim_win_get_config(0)
  eq({ config.width, config.height, config.row, config.col }, { 12, 4, 0, 0 })
end

T["fractional cell dimensions"] = test.new_set({
  parametrize = { { "numbers" }, { "callbacks" } },
}, {
  ---@param kind string
  ["round down on opening and resizing without rounding coordinates"] = function(kind)
    restore_editor_size()
    resize_editor(81, 41)
    ---@type gents.FloatConfig
    local opts = { width = 72.9, height = 36.9, row = 0.5, col = 0.5 }
    if kind == "callbacks" then
      opts.width = function()
        return vim.o.columns * 0.9
      end
      opts.height = function()
        return vim.o.lines * 0.9
      end
    end
    H.new({ layout = opts })
    local win = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(win)
    eq({ config.width, config.height, config.row, config.col }, { 72, 36, 0.5, 0.5 })

    resize_editor(82, 42)

    config = vim.api.nvim_win_get_config(win)
    local width, height = kind == "callbacks" and 73 or 72, kind == "callbacks" and 37 or 36
    eq({ config.width, config.height, config.row, config.col }, { width, height, 0.5, 0.5 })
  end,
})

T["float callbacks run on opening and resizing using numeric geometry rules"] = function()
  restore_editor_size()
  resize_editor(80, 40)
  local calls = { width = 0, height = 0, row = 0, col = 0 }
  local opts = {
    width = function()
      calls.width = calls.width + 1
      return 0.5
    end,
    height = function()
      calls.height = calls.height + 1
      return 0.25
    end,
    row = function()
      calls.row = calls.row + 1
      return vim.o.lines / 8
    end,
    col = function()
      calls.col = calls.col + 1
      return 0.5
    end,
  }
  local original = vim.deepcopy(opts)
  H.new({ layout = opts })
  local win = vim.api.nvim_get_current_win()
  local config = vim.api.nvim_win_get_config(win)
  eq(calls, { width = 1, height = 1, row = 1, col = 1 })
  eq({ config.width, config.height, config.row, config.col }, { 40, 10, 5, 0.5 })
  local resized = 0
  local autocmd = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      resized = resized + 1
    end,
  })
  test.finally(function()
    vim.api.nvim_del_autocmd(autocmd)
  end)

  resize_editor(120, 60)

  config = vim.api.nvim_win_get_config(win)
  eq(resized > 0, true)
  eq(calls, { width = 1 + resized, height = 1 + resized, row = 1 + resized, col = 1 + resized })
  eq({ config.width, config.height, config.row, config.col }, { 60, 15, 7.5, 0.5 })
  eq(opts, original)
end

T["each float retains its own geometry when options and setup change"] = function()
  restore_editor_size()
  resize_editor(80, 40)
  local source = vim.api.nvim_get_current_win()
  gents.setup({ float = { width = 0.25, height = 0.5 }, tools = { cat = { cmd = { "cat" } } } })
  local first = H.new({ layout = "float" })
  local first_win = vim.api.nvim_get_current_win()
  local inline = { width = 0.5, height = 8, row = 1, col = 2 }
  gents.show(first.id, { layout = inline })
  local second_win = vim.api.nvim_get_current_win()
  local second = H.new({ layout = { width = 10, height = 4, row = 2, col = 3 } })
  local third_win = vim.api.nvim_get_current_win()
  inline.width = 90
  require("gents.config").get().float.width = 90
  gents.setup({ float = { width = 11, height = 5 } })
  vim.api.nvim_set_current_win(source)

  resize_editor(120, 60)

  local a, b, c =
    vim.api.nvim_win_get_config(first_win),
    vim.api.nvim_win_get_config(second_win),
    vim.api.nvim_win_get_config(third_win)
  eq({ a.width, a.height, a.row, a.col }, { 30, 30, 15, 45 })
  eq({ b.width, b.height, b.row, b.col }, { 60, 8, 1, 2 })
  eq({ c.width, c.height, c.row, c.col }, { 10, 4, 2, 3 })
  eq(vim.api.nvim_get_current_win(), source)
  eq(vim.api.nvim_win_get_buf(first_win), first.buf)
  eq(vim.api.nvim_win_get_buf(second_win), first.buf)
  eq(vim.api.nvim_win_get_buf(third_win), second.buf)
  eq(gents.sessions(), { first, second })
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["floats in another tab"] = test.new_set({
  parametrize = { { "editor" }, { "win" } },
}, {
  ---@param relative "editor"|"win"
  ["resize without changing tabs, focus, mode, buffers, or jobs"] = function(relative)
    restore_editor_size()
    resize_editor(80, 40)
    local source = vim.api.nvim_get_current_win()
    local session = H.new({
      layout = {
        relative = relative,
        win = relative == "win" and source or nil,
        width = 0.5,
        height = 0.25,
      },
    })
    local float, session_tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    local buf, job = session.buf, session.job
    vim.cmd.tabnew()
    vim.cmd.stopinsert()
    local current, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    local current_buf, mode = vim.api.nvim_get_current_buf(), vim.api.nvim_get_mode().mode
    eq(tab ~= session_tab, true)

    resize_editor(120, 60)

    local config = vim.api.nvim_win_get_config(float)
    eq({ config.width, config.height, config.row, config.col }, { 60, 15, 22, 30 })
    eq(config.relative, relative)
    if relative == "win" then
      eq(config.win, source)
    end
    eq(vim.api.nvim_get_current_win(), current)
    eq(vim.api.nvim_get_current_tabpage(), tab)
    eq(vim.api.nvim_get_mode().mode, mode)
    eq(vim.api.nvim_get_current_buf(), current_buf)
    eq(vim.api.nvim_win_get_tabpage(float), session_tab)
    eq(vim.api.nvim_win_get_buf(float), buf)
    eq({ session.buf, session.job, session.tab }, { buf, job, session_tab })
    eq(vim.fn.jobwait({ job }, 0), { -1 })
  end,
})

T["floats created by a layout callback keep their own geometry"] = function()
  restore_editor_size()
  resize_editor(80, 40)
  local calls = 0
  H.new({
    layout = function()
      calls = calls + 1
      return vim.api.nvim_open_win(
        0,
        true,
        { relative = "editor", width = 12, height = 4, row = 1, col = 2 }
      )
    end,
  })
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_config(win, { relative = "editor", width = 17, row = 3, col = 4 })

  resize_editor(120, 60)

  local config = vim.api.nvim_win_get_config(win)
  eq({ config.width, config.height, config.row, config.col }, { 17, 4, 3, 4 })
  eq(calls, 1)
end

T["cursor-relative floats keep their original anchor while resizing from another window"] = function()
  restore_editor_size()
  resize_editor(80, 40)
  local source = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second", "third" })
  vim.api.nvim_win_set_cursor(source, { 3, 4 })
  local session = H.new({
    layout = { relative = "cursor", width = 0.5, height = 0.25, row = 1, col = 2 },
  })
  local win = vim.api.nvim_get_current_win()
  local original = vim.api.nvim_win_get_config(win)
  vim.api.nvim_set_current_win(source)
  vim.api.nvim_win_set_cursor(source, { 1, 0 })
  vim.cmd.vsplit()
  local current = vim.api.nvim_get_current_win()

  resize_editor(120, 60)

  local resized = vim.api.nvim_win_get_config(win)
  eq({ resized.width, resized.height }, { 60, 15 })
  eq(
    { resized.relative, resized.win, resized.anchor, resized.row, resized.col },
    { original.relative, original.win, original.anchor, original.row, original.col }
  )
  eq(vim.api.nvim_get_current_win(), current)
  eq(vim.api.nvim_win_get_buf(win), session.buf)
end

T["window-relative floats retain their buffer anchor even after its window closes"] = function()
  restore_editor_size()
  resize_editor(80, 40)
  local source = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second", "third" })
  local session = H.new({
    layout = {
      relative = "win",
      win = source,
      bufpos = { 2, 2 },
      width = 0.5,
      height = 0.25,
      row = 1,
      col = 2,
    },
  })
  local win = vim.api.nvim_get_current_win()
  local original = vim.api.nvim_win_get_config(win)

  vim.api.nvim_exec_autocmds("VimResized", {})

  local resized = vim.api.nvim_win_get_config(win)
  eq(resized.bufpos, { 2, 2 })
  eq({ resized.relative, resized.win, resized.row, resized.col }, {
    "win",
    source,
    original.row,
    original.col,
  })
  vim.api.nvim_set_current_win(source)
  vim.cmd.vsplit()
  local current, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
  local notifications = 0
  local notify = vim.notify
  set_notify(function()
    notifications = notifications + 1
  end)
  test.finally(function()
    set_notify(notify)
  end)
  vim.api.nvim_win_close(source, true)
  local detached = vim.api.nvim_win_get_config(win)

  resize_editor(120, 60)

  resized = vim.api.nvim_win_get_config(win)
  eq({ resized.width, resized.height }, { 60, 15 })
  eq(resized.bufpos, { 2, 2 })
  eq({ resized.relative, resized.win, resized.row, resized.col }, {
    "win",
    source,
    detached.row,
    detached.col,
  })
  eq(notifications, 0)
  eq(vim.api.nvim_get_current_win(), current)
  eq(vim.api.nvim_get_current_tabpage(), tab)
  eq(vim.api.nvim_win_get_buf(win), session.buf)
end

T["a failing geometry callback leaves other floats resizing and can recover"] = function()
  local width, failing = 20, false
  local broken = H.new({
    layout = {
      width = function()
        assert(not failing, "test geometry failure")
        return width
      end,
      height = 5,
    },
  })
  local broken_win = vim.api.nvim_get_current_win()
  local healthy = H.new({
    layout = {
      width = function()
        return width + 10
      end,
      height = 5,
    },
  })
  local healthy_win = vim.api.nvim_get_current_win()
  ---@type { message: string, level?: integer }[]
  local notifications = {}
  local notify = vim.notify
  set_notify(function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
  end)
  test.finally(function()
    set_notify(notify)
  end)
  width, failing = 30, true

  vim.api.nvim_exec_autocmds("VimResized", {})

  eq(vim.api.nvim_win_get_width(broken_win), 20)
  eq(vim.api.nvim_win_get_width(healthy_win), 40)
  eq(#notifications, 1)
  eq(notifications[1].level, vim.log.levels.ERROR)
  eq(notifications[1].message:find("test geometry failure", 1, true) ~= nil, true)
  failing = false

  vim.api.nvim_exec_autocmds("VimResized", {})

  eq(vim.api.nvim_win_get_width(broken_win), 30)
  eq(vim.api.nvim_win_get_width(healthy_win), 40)
  eq(#notifications, 1)
  eq(vim.fn.jobwait({ broken.job, healthy.job }, 0), { -1, -1 })
end

T["removed float windows"] = test.new_set({
  parametrize = { { "native close" }, { "hide" }, { "close" } },
}, {
  ---@param action string
  ["stop evaluating geometry callbacks"] = function(action)
    local calls = 0
    local session = H.new({
      layout = {
        width = function()
          calls = calls + 1
          return 0.5
        end,
        height = 0.5,
      },
    })
    local win = vim.api.nvim_get_current_win()
    eq(calls, 1)
    if action == "native close" then
      vim.api.nvim_win_close(win, true)
    elseif action == "hide" then
      gents.hide(session.id)
    else
      gents.close(session.id)
    end

    vim.api.nvim_exec_autocmds("VimResized", {})

    eq(vim.api.nvim_win_is_valid(win), false)
    eq(calls, 1)
    if action ~= "close" then
      eq(gents.sessions(), { session })
      eq(vim.fn.jobwait({ session.job }, 0), { -1 })
    end
  end,
})

T["tiny editor float geometry"] = test.new_set({
  parametrize = { { "fractions" }, { "callbacks" } },
}, {
  ---@param kind string
  ["stays valid and recovers after expanding the editor"] = function(kind)
    restore_editor_size()
    resize_editor(80, 40)
    ---@type gents.FloatConfig
    local opts = { width = 0.5, height = 0.25, border = "single" }
    if kind == "callbacks" then
      opts.width = function()
        return vim.o.columns - 4
      end
      opts.height = function()
        return vim.o.lines - 4
      end
    end
    local session = H.new({ layout = opts })
    local win = vim.api.nvim_get_current_win()
    local original = vim.api.nvim_win_get_config(win)

    resize_editor(12, 3)

    local small = vim.api.nvim_win_get_config(win)
    eq(small.width >= 1 and small.width <= vim.o.columns, true)
    eq(small.height, 1)
    eq(vim.api.nvim_win_get_buf(win), session.buf)
    eq(vim.fn.jobwait({ session.job }, 0), { -1 })

    resize_editor(80, 40)

    local expanded = vim.api.nvim_win_get_config(win)
    eq(
      { expanded.width, expanded.height, expanded.row, expanded.col },
      { original.width, original.height, original.row, original.col }
    )
    eq(vim.api.nvim_win_get_buf(win), session.buf)
    eq(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
})

T["show without a layout reuses an existing window in another tab"] = function()
  local session = H.new({ layout = "tabnew" })
  local win, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
  vim.cmd.tabprevious()
  gents.show(session.id)
  eq(vim.api.nvim_get_current_win(), win)
  eq(vim.api.nvim_get_current_tabpage(), tab)
  eq(vim.fn.win_findbuf(session.buf), { win })
end

T["an explicit show layout opens a view without leaving the invoking tab"] = function()
  local session = H.new()
  local existing = vim.api.nvim_get_current_win()
  vim.cmd.tabnew()
  local tab = vim.api.nvim_get_current_tabpage()
  gents.show(session.id, { layout = "float" })
  eq(vim.api.nvim_get_current_tabpage(), tab)
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_win_get_buf(existing), session.buf)
  eq(#vim.fn.win_findbuf(session.buf), 2)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["hide closes a sole-window tab and keeps its job running"] = function()
  local session = H.new({ layout = "tabnew" })
  local tab = vim.api.nvim_get_current_tabpage()
  gents.hide(session.id)
  eq(vim.api.nvim_tabpage_is_valid(tab), false)
  eq(window.visible(session), false)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["hide uses the alternate buffer in the final window"] = function()
  local original = vim.api.nvim_get_current_buf()
  local session = H.new({ layout = "current" })
  gents.hide(session.id)
  eq(vim.api.nvim_get_current_buf(), original)
  eq(#vim.api.nvim_list_wins(), 1)
  eq(window.visible(session), false)
end

T["hide creates an empty buffer when no alternate survives"] = function()
  local original = vim.api.nvim_get_current_buf()
  local session = H.new({ layout = "current" })
  vim.api.nvim_buf_delete(original, { force = true })
  gents.hide(session.id)
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

    gents[first_action](first.id)
    eq(#vim.api.nvim_list_wins(), 1)
    eq(vim.api.nvim_get_current_buf(), second.buf)
    gents.hide(second.id)

    eq(window.visible(first), false)
    eq(window.visible(second), false)
    eq(#vim.api.nvim_list_wins(), 1)
    eq(vim.bo.buftype, "")
    eq(vim.api.nvim_buf_get_name(0), "")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    eq(gents.current(), nil)
    eq(vim.fn.jobwait({ second.job }, 0), { -1 })
    if first_action == "hide" then
      eq(gents.sessions(), { first, second })
      eq(vim.fn.jobwait({ first.job }, 0), { -1 })
    else
      eq(gents.sessions(), { second })
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
    local group = vim.api.nvim_create_augroup("GentsRenamedTerminalTest", { clear = true })
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

    gents[action](session.id)
    if action == "close" then
      H.wait(function()
        return session.state == "exited" and not vim.api.nvim_buf_is_valid(session.buf)
      end)
      eq(gents.sessions(), {})
      eq(vim.fn.jobwait({ session.job }, 0)[1] ~= -1, true)
    else
      eq(gents.sessions(), { session })
      eq(vim.fn.jobwait({ session.job }, 0), { -1 })
      eq(window.visible(session), false)
    end
    eq(starts, 1)
    eq(#vim.api.nvim_list_wins(), 1)
    eq(vim.bo.buftype, "")
    eq(vim.api.nvim_buf_get_name(0), "")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    eq(gents.current(), nil)
  end,
})

T["hide removes only current-tab views of a shared session"] = function()
  local session = H.new()
  local tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.split()
  vim.cmd.tabnew()
  vim.api.nvim_win_set_buf(0, session.buf)
  local elsewhere = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_tabpage(tab)
  eq(#vim.fn.win_findbuf(session.buf), 3)
  gents.hide(session.id)
  eq(vim.fn.win_findbuf(session.buf), { elsewhere })
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["hide ignores existing nonvisible targets and rejects unknown targets"] = function()
  local session = H.new()
  local win = vim.api.nvim_get_current_win()
  vim.cmd.tabnew()
  eq(gents.ready(session.id).visible, false)
  eq(gents.hide(session.id), nil)
  eq(gents.hide(session.label), nil)
  eq(
    gents.hide(function(candidate)
      return candidate.id == session.id
    end),
    nil
  )
  eq(gents.hide(), nil)
  eq(vim.fn.win_findbuf(session.buf), { win })
  test.expect.error(function()
    gents.hide("missing")
  end, "no session matches target")
  test.expect.error(function()
    gents.hide(session.id, { all = true })
  end, "cannot be combined with a target")
end

T["hide all removes splits floats and duplicate views while preserving other tabs"] = function()
  local first = H.new()
  vim.cmd.split()
  local second = H.new({ layout = "float" })
  local tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  vim.api.nvim_win_set_buf(0, first.buf)
  local shared = vim.api.nvim_get_current_win()
  local elsewhere = H.new()
  vim.api.nvim_set_current_tabpage(tab)
  eq(gents.hide(nil, { all = true }), nil)
  eq(window.visible(first, tab), false)
  eq(window.visible(second, tab), false)
  eq(vim.fn.win_findbuf(first.buf), { shared })
  eq(#vim.fn.win_findbuf(elsewhere.buf), 1)
  eq(vim.fn.jobwait({ first.job, second.job, elsewhere.job }, 0), { -1, -1, -1 })
  eq(gents.hide(nil, { all = true }), nil)
end

T["hide all stays in its original tab when the tab closes"] = function()
  local first = H.new({ layout = "tabnew" })
  local tab = vim.api.nvim_get_current_tabpage()
  local second = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_tabpage(tab)
  gents.hide(nil, { all = true })
  eq(vim.api.nvim_tabpage_is_valid(tab), false)
  eq(#vim.fn.win_findbuf(first.buf), 0)
  eq(#vim.fn.win_findbuf(second.buf), 1)
end

T["hide all replaces the last agent window without reopening another agent"] = function()
  local first = H.new({ layout = "current" })
  local second = H.new()
  gents.hide(nil, { all = true })
  eq(window.visible(first), false)
  eq(window.visible(second), false)
  eq(#vim.api.nvim_list_wins(), 1)
  eq(vim.bo.buftype, "")
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["native buffer replacement hides a session without plugin involvement"] = function()
  local original = vim.api.nvim_get_current_buf()
  local session = H.new()
  vim.cmd.buffer(original)
  eq(window.visible(session), false)
  eq(gents.current(), nil)
  eq(gents.sessions(), { session })
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["TermOpen and filetype customizations are preserved"] = function()
  local group = vim.api.nvim_create_augroup("GentsWindowTest", { clear = true })
  test.finally(function()
    vim.api.nvim_del_augroup_by_id(group)
  end)
  ---@type integer?
  local observed
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      observed = vim.b[ev.buf].gents_session
      vim.wo.number = true
      vim.wo.signcolumn = "yes:2"
      vim.wo.winfixwidth = true
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "gents_terminal",
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
