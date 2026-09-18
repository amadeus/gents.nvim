local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local window = require("gents.window")
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
local eq = test.expect.equality

---@return fun(): gents.PickerSpec<gents.Session|gents.Tool>
local function capture_picker()
  ---@type gents.PickerSpec<gents.Session|gents.Tool>?
  local spec
  require("gents.config").get().picker = function(value)
    spec = value
  end
  return function()
    return assert(spec, "Expected a picker to open")
  end
end

T["focus leaves the current session visible and returns to the previous window"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new()
  local terminal = vim.api.nvim_get_current_win()

  gents.focus()

  eq(vim.api.nvim_get_current_win(), original)
  eq(vim.api.nvim_win_get_buf(terminal), session.buf)
  eq(window.visible(session), true)
  eq(#gents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["focus with no sessions opens the tool picker"] = function()
  local picked = capture_picker()

  gents.focus()

  eq(picked().title, "Gents: New Session")
  eq(#gents.sessions(), 0)
end

T["focus shows a sole hidden session"] = function()
  local session = H.new()
  gents.hide(session.id)

  eq(gents.focus(), session)

  eq(gents.current(), session)
  eq(window.visible(session), true)
  eq(#gents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["focus opens the picker when one session is visible here and another exists elsewhere"] = function()
  local original = vim.api.nvim_get_current_win()
  local here = H.new()
  local terminal = vim.api.nvim_get_current_win()
  local elsewhere = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_win(original)
  local picked = capture_picker()

  eq(gents.focus(), nil)
  eq(vim.api.nvim_get_current_win(), original)
  local spec = picked()
  eq(#spec.items, 2)
  spec.actions[spec.default](spec.items[1])

  eq(vim.api.nvim_get_current_win(), terminal)
  eq(gents.current(), here)
  eq(window.visible(elsewhere), false)
  eq(window.visible(elsewhere, elsewhere.tab), true)
  eq(#gents.sessions(), 2)
  eq(vim.fn.jobwait({ here.job, elsewhere.job }, 0), { -1, -1 })
end

T["explicit focus targets show the requested session even from an agent buffer"] = function()
  local first = H.new()
  local second = H.new()

  eq(gents.focus(first.label), first)
  eq(gents.current(), first)
  eq(window.visible(second), true)
  eq(gents.focus(first.id), first)
  eq(gents.current(), first)
end

T["focus opens the session picker when several sessions are hidden"] = function()
  local first = H.new()
  local second = H.new()
  gents.hide(first.id)
  gents.hide(second.id)
  local picked = capture_picker()

  gents.focus()

  eq(#picked().items, 2)
  eq(gents.current(), nil)
  eq(window.visible(first), false)
  eq(window.visible(second), false)
  eq(#gents.sessions(), 2)
  local spec = picked()
  spec.actions[spec.default](spec.items[1])
  eq(gents.current(), first)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["toggle hides only the current-tab views of the session under the cursor"] = function()
  local tab = vim.api.nvim_get_current_tabpage()
  local other = H.new()
  local session = H.new()
  local current = vim.api.nvim_get_current_win()
  window.open(session.buf, "tabnew")
  local elsewhere = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(current)
  gents.toggle()
  eq(window.visible(session, tab), false)
  eq(window.visible(session, elsewhere), true)
  eq(window.visible(other, tab), true)
  eq(#gents.sessions(), 2)
  eq(vim.fn.jobwait({ session.job, other.job }, 0), { -1, -1 })
end

T["toggle with no sessions opens the tool picker"] = function()
  local picked = capture_picker()
  gents.toggle()
  eq(picked() ~= nil, true)
  eq(#gents.sessions(), 0)
end

T["toggle from an editor buffer hides the sole visible session"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(original)
  gents.toggle()
  eq(window.visible(session), false)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#gents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["toggle from an editor buffer hides all current-tab views without a picker"] = function()
  local original = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local first = H.new()
  vim.cmd.split()
  local second = H.new({ layout = "float" })
  local hidden = H.new()
  gents.hide(hidden.id)
  local remote = H.new({ layout = "tabnew" })
  local elsewhere = vim.api.nvim_get_current_tabpage()
  window.open(first.buf, "vsplit")
  vim.api.nvim_set_current_win(original)
  require("gents.config").get().picker = function()
    error("Toggle must not open a picker when hiding visible sessions")
  end

  vim.cmd("Gents toggle")

  eq(window.visible(first, tab), false)
  eq(window.visible(second, tab), false)
  eq(window.visible(hidden, tab), false)
  eq(window.visible(first, elsewhere), true)
  eq(window.visible(remote, elsewhere), true)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#gents.sessions(), 4)
  eq(vim.fn.jobwait({ first.job, second.job, hidden.job, remote.job }, 0), { -1, -1, -1, -1 })
end

T["explicit toggle hides only the target views in the current tab"] = function()
  local original = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local shared = H.new()
  local here = H.new()
  local remote = H.new({ layout = "tabnew" })
  local elsewhere = vim.api.nvim_get_current_tabpage()
  window.open(shared.buf, "vsplit")
  vim.api.nvim_set_current_win(original)

  gents.toggle(shared.label)

  eq(window.visible(shared, tab), false)
  eq(window.visible(shared, elsewhere), true)
  eq(window.visible(here), true)
  eq(window.visible(remote, elsewhere), true)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#gents.sessions(), 3)
  eq(vim.fn.jobwait({ shared.job, here.job, remote.job }, 0), { -1, -1, -1 })
end

T["explicit toggle targets override the current agent"] = function()
  local first = H.new()
  local current = H.new()

  eq(gents.toggle(first.id), first)
  eq(window.visible(first), false)
  eq(gents.current(), current)
  eq(window.visible(current), true)

  eq(gents.toggle(first.label), first)
  eq(gents.current(), first)
  eq(window.visible(current), true)
end

T["toggle shows a sole hidden session"] = function()
  local session = H.new()
  gents.hide(session.id)
  gents.toggle()
  eq(gents.current(), session)
  eq(window.visible(session), true)
  eq(#gents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["toggle restores floats after hiding"] = test.new_set({
  parametrize = { { "toggle" }, { "hide" }, { "native close" } },
}, {
  ---@param action string
  ["keeps the session and its floating placement"] = function(action)
    local session = H.new({ layout = "float" })
    local buf, job = session.buf, session.job
    for _ = 1, 2 do
      if action == "native close" then
        vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
      elseif action == "hide" then
        gents.hide(session.id)
      else
        gents.toggle(session.id)
      end
      eq(window.visible(session), false)
      gents.toggle(session.id)
      eq(vim.api.nvim_win_get_config(0).relative, "editor")
      eq(vim.api.nvim_get_current_buf(), buf)
      eq(session.job, job)
      eq(vim.fn.jobwait({ job }, 0), { -1 })
    end
  end,
})

T["toggle float restoration can be disabled per call"] = test.new_set({
  parametrize = {
    { {}, "editor" },
    { { layout = "float" }, "editor" },
    { { layout = false }, "" },
    { { layout = "vsplit" }, "" },
  },
}, {
  ---@param opts gents.ToggleOptions
  ---@param relative string
  ["only controls reopening"] = function(opts, relative)
    local session = H.new({ layout = "float" })
    gents.toggle(session.id, opts)
    eq(window.visible(session), false)
    eq(session.last_float, true)
    gents.toggle(session.id, opts)
    eq(vim.api.nvim_win_get_config(0).relative, relative)
    eq(vim.api.nvim_get_current_buf(), session.buf)
    -- Reopening still records the actual placement for later default toggles.
    gents.toggle(session.id)
    gents.toggle(session.id)
    eq(vim.api.nvim_win_get_config(0).relative, relative)
  end,
})

T["toggle preserves the float opt-out through session selection"] = function()
  local first = H.new({ layout = "float" })
  gents.hide(first.id)
  local second = H.new({ layout = "float" })
  gents.hide(second.id)
  local picked = capture_picker()
  gents.toggle(nil, { layout = false })
  local spec = picked()
  spec.actions[spec.default](spec.items[1])
  eq(vim.api.nvim_get_current_buf(), first.buf)
  eq(vim.api.nvim_win_get_config(0).relative, "")
  eq(window.visible(second), false)
end

T["toggle float opt-out still uses a floating default layout"] = function()
  local session = H.new({ layout = "float" })
  gents.hide(session.id)
  require("gents.config").get().layout = "float"
  gents.toggle(nil, { layout = false })
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
end

T["toggle float opt-out reuses existing views in other tabs"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  -- Keep the tab open while cleanup removes the session's split and float.
  vim.cmd.new()
  gents.show(session.id, { layout = "float" })
  local wins = vim.fn.win_findbuf(session.buf)
  vim.api.nvim_set_current_win(original)
  gents.toggle(session.id, { layout = false })
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.fn.win_findbuf(session.buf), wins)
end

T["toggle accepts the documented layout forms"] = test.new_set({
  parametrize = {
    { "split", "" },
    { "tabnew", "" },
    { "current", "" },
    { { width = 24, height = 6, row = 1, col = 2 }, "editor", 24 },
    {
      ---@return integer
      function()
        return vim.api.nvim_open_win(
          0,
          true,
          { relative = "editor", width = 24, height = 6, row = 1, col = 2 }
        )
      end,
      "editor",
      24,
    },
  },
}, {
  ---@param layout gents.Layout
  ---@param relative string
  ---@param width? integer
  ["shows the existing session at the requested placement"] = function(layout, relative, width)
    local session = H.new({ layout = "float" })
    gents.hide(session.id)
    gents.toggle(session.id, { layout = layout })
    eq(vim.api.nvim_get_current_buf(), session.buf)
    eq(vim.api.nvim_win_get_config(0).relative, relative)
    if width then
      eq(vim.api.nvim_win_get_width(0), width)
    end
    eq(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
})

T["toggle explicit layout preserves views in other tabs"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  local remote = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(original)
  gents.toggle(session.id, { layout = "float" })
  eq(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(original))
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
  eq(vim.api.nvim_win_get_buf(remote), session.buf)
  eq(#vim.fn.win_findbuf(session.buf), 2)
  gents.toggle(session.id, { layout = "vsplit" })
  eq(vim.fn.win_findbuf(session.buf), { remote })
end

T["toggle explicit layout survives session selection"] = function()
  local first = H.new()
  gents.hide(first.id)
  local second = H.new()
  gents.hide(second.id)
  local picked = capture_picker()
  gents.toggle(nil, { layout = { width = 24, height = 6 } })
  local spec = picked()
  spec.actions[spec.default](spec.items[1])
  eq(vim.api.nvim_get_current_buf(), first.buf)
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
  eq(vim.api.nvim_win_get_width(0), 24)
  eq(window.visible(second), false)
end

T["toggle carries placement into the New Session picker"] = test.new_set({
  parametrize = {
    { false, "" },
    { "float", "editor" },
    { { width = 24, height = 6 }, "editor", 24 },
  },
}, {
  ---@param layout gents.Layout|false
  ---@param relative string
  ---@param width? integer
  ["launches at the requested placement"] = function(layout, relative, width)
    local config = require("gents.config").get()
    config.tools = { cat = assert(config.tools.cat) }
    local picked = capture_picker()
    gents.toggle(nil, { layout = layout })
    local spec = picked()
    eq(spec.title, "Gents: New Session")
    eq(#spec.items, 1)
    spec.actions[spec.default](spec.items[1])
    local session = assert(gents.current())
    eq(session.tool.name, "cat")
    eq(vim.api.nvim_win_get_config(0).relative, relative)
    if width then
      eq(vim.api.nvim_win_get_width(0), width)
    end
  end,
})

T["toggle restores custom floats using current float defaults"] = test.new_set({
  parametrize = {
    { { width = 12, height = 4, row = 0, col = 0 } },
    {
      ---@return integer
      function()
        return vim.api.nvim_open_win(
          0,
          true,
          { relative = "editor", width = 12, height = 4, row = 0, col = 0 }
        )
      end,
    },
  },
}, {
  ---@param layout gents.Layout
  ["uses the resulting window type"] = function(layout)
    local session = H.new({ layout = layout })
    gents.toggle(session.id)
    require("gents.config").get().float.width = function()
      return 30
    end
    gents.toggle(session.id)
    eq(vim.api.nvim_win_get_config(0).relative, "editor")
    eq(vim.api.nvim_win_get_width(0), 30)
  end,
})

T["toggle remembers the most recent placement among multiple views"] = test.new_set({
  parametrize = { { "float", "vsplit", "" }, { "vsplit", "float", "editor" } },
}, {
  ---@param initial string
  ---@param latest string
  ---@param relative string
  ["updates through show and picker placement"] = function(initial, latest, relative)
    local original = vim.api.nvim_get_current_win()
    local session = H.new({ layout = initial })
    vim.api.nvim_set_current_win(original)
    gents.show(session.id, { layout = latest })
    eq(#vim.fn.win_findbuf(session.buf), 2)
    gents.toggle(session.id)
    gents.toggle(session.id)
    eq(vim.api.nvim_win_get_config(0).relative, relative)

    vim.api.nvim_set_current_win(original)
    local picked = capture_picker()
    gents.pick()
    local spec = picked()
    spec.actions[initial](spec.items[1])
    gents.toggle(session.id)
    gents.toggle(session.id)
    eq(vim.api.nvim_win_get_config(0).relative, initial == "float" and "editor" or "")
  end,
})

T["toggle remembers placement independently for each session"] = function()
  local floating = H.new({ layout = "float" })
  gents.hide(floating.id)
  local split = H.new()
  gents.hide(split.id)
  gents.toggle(floating.id)
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
  gents.hide(floating.id)
  gents.toggle(split.id)
  eq(vim.api.nvim_win_get_config(0).relative, "")
end

T["toggle uses the current default layout after a non-floating placement"] = function()
  local session = H.new()
  gents.hide(session.id)
  require("gents.config").get().layout = "float"
  gents.toggle(session.id)
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
end

T["show and focus reopen hidden floats using the default layout"] = test.new_set({
  parametrize = { { gents.show }, { gents.focus } },
}, {
  ---@param action fun(target?: gents.Target): gents.Session?
  ["also updates the placement remembered by toggle"] = function(action)
    local session = H.new({ layout = "float" })
    gents.hide(session.id)
    action(session.id)
    eq(vim.api.nvim_win_get_config(0).relative, "")
    gents.toggle(session.id)
    gents.toggle(session.id)
    eq(vim.api.nvim_win_get_config(0).relative, "")
  end,
})

T["toggle reuses a view in another tab despite remembered float placement"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  local remote = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(original)
  gents.show(session.id, { layout = "float" })
  gents.toggle(session.id)
  eq(vim.api.nvim_win_is_valid(remote), true)
  gents.toggle(session.id)
  eq(vim.api.nvim_get_current_win(), remote)
  eq(vim.fn.win_findbuf(session.buf), { remote })
end

T["toggle shows the sole session even when it is visible in another tab"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_win(original)

  gents.toggle()

  eq(gents.current(), session)
  eq(window.visible(session), true)
  eq(#gents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["toggle opens the session picker when several sessions are hidden"] = function()
  local first = H.new()
  local second = H.new()
  gents.hide(first.id)
  gents.hide(second.id)
  local picked = capture_picker()
  gents.toggle()
  eq(#picked().items, 2)
  eq(gents.current(), nil)
  eq(window.visible(first), false)
  eq(window.visible(second), false)
  eq(#gents.sessions(), 2)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["toggle opens the session picker when multiple sessions are visible only in another tab"] = function()
  local original = vim.api.nvim_get_current_win()
  local first = H.new({ layout = "tabnew" })
  local second = H.new()
  local elsewhere = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(original)
  local picked = capture_picker()

  gents.toggle()

  eq(#picked().items, 2)
  eq(vim.api.nvim_get_current_win(), original)
  eq(window.visible(first, elsewhere), true)
  eq(window.visible(second, elsewhere), true)
  eq(#gents.sessions(), 2)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["pick always opens a picker even for one session"] = function()
  local session = H.new()
  local picked = capture_picker()
  gents.pick()
  eq(#picked().items, 1)
  eq(picked().items[1].data.id, session.id)
end

T["explicit pick targets show the requested session without opening a picker"] = function()
  local first = H.new()
  H.new()
  gents.hide(first.id)
  require("gents.config").get().picker = function()
    error("Expected an explicit target to skip the picker")
  end

  eq(gents.pick(first.label), first)
  eq(gents.current(), first)
end

T["explicit unmatched targets do not create sessions"] = function()
  require("gents.config").get().picker = function()
    error("Expected an explicit unmatched target to error")
  end
  for _, action in ipairs({ gents.pick, gents.focus, gents.toggle }) do
    test.expect.error(function()
      action("missing")
    end, "no session matches")
  end
  eq(#gents.sessions(), 0)
end

T["pick falls through to the tool picker when empty"] = function()
  local picked = capture_picker()
  gents.pick()
  local names = vim.tbl_map(
    ---@param item gents.PickerItem<gents.Tool>
    ---@return string
    function(item)
      return item.data.name
    end,
    picked().items
  )
  eq(vim.tbl_contains(names, "cat"), true)
end

return T
