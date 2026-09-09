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

T["toggle from an editor buffer picks one session to hide and preserves the others"] = function()
  local original = vim.api.nvim_get_current_win()
  local first = H.new()
  local second = H.new()
  local hidden = H.new()
  gents.hide(hidden.id)
  vim.api.nvim_set_current_win(original)
  local picked = capture_picker()

  gents.toggle()

  eq(window.visible(first), true)
  eq(window.visible(second), true)
  local spec = picked()
  eq(#spec.items, 3)
  spec.actions[spec.default](spec.items[1])
  eq(window.visible(first), false)
  eq(window.visible(second), true)
  eq(window.visible(hidden), false)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#gents.sessions(), 3)
  eq(vim.fn.jobwait({ first.job, second.job, hidden.job }, 0), { -1, -1, -1 })
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
