local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local window = require("agents.window")
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
local eq = test.expect.equality

---@return fun(): agents.PickerSpec<agents.Session|agents.Tool>
local function capture_picker()
  ---@type agents.PickerSpec<agents.Session|agents.Tool>?
  local spec
  require("agents.config").get().picker = function(value)
    spec = value
  end
  return function()
    return assert(spec, "Expected a picker to open")
  end
end

T["toggle hides only the current-tab views of the session under the cursor"] = function()
  local tab = vim.api.nvim_get_current_tabpage()
  local other = H.new()
  local session = H.new()
  local current = vim.api.nvim_get_current_win()
  window.open(session.buf, "tabnew")
  local elsewhere = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(current)
  agents.toggle()
  eq(window.visible(session, tab), false)
  eq(window.visible(session, elsewhere), true)
  eq(window.visible(other, tab), true)
  eq(#agents.sessions(), 2)
  eq(vim.fn.jobwait({ session.job, other.job }, 0), { -1, -1 })
end

T["toggle with no sessions opens the tool picker"] = function()
  local picked = capture_picker()
  agents.toggle()
  eq(picked() ~= nil, true)
  eq(#agents.sessions(), 0)
end

T["toggle from an editor buffer hides the sole visible session"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(original)
  agents.toggle()
  eq(window.visible(session), false)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#agents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["toggle from an editor buffer hides all visible sessions and leaves hidden sessions alone"] = function()
  local original = vim.api.nvim_get_current_win()
  local first = H.new()
  local second = H.new()
  local hidden = H.new()
  agents.hide(hidden.id)
  vim.api.nvim_set_current_win(original)
  require("agents.config").get().picker = function()
    error("Expected visible sessions to hide without opening a picker")
  end

  agents.toggle()

  eq(window.visible(first), false)
  eq(window.visible(second), false)
  eq(window.visible(hidden), false)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#agents.sessions(), 3)
  eq(vim.fn.jobwait({ first.job, second.job, hidden.job }, 0), { -1, -1, -1 })
end

T["toggle from an editor buffer preserves session views in other tabs"] = function()
  local original = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local shared = H.new()
  local here = H.new()
  local remote = H.new({ layout = "tabnew" })
  local elsewhere = vim.api.nvim_get_current_tabpage()
  window.open(shared.buf, "vsplit")
  vim.api.nvim_set_current_win(original)

  agents.toggle()

  eq(window.visible(shared, tab), false)
  eq(window.visible(shared, elsewhere), true)
  eq(window.visible(here), false)
  eq(window.visible(remote, elsewhere), true)
  eq(vim.api.nvim_get_current_win(), original)
  eq(#agents.sessions(), 3)
  eq(vim.fn.jobwait({ shared.job, here.job, remote.job }, 0), { -1, -1, -1 })
end

T["toggle shows a sole hidden session"] = function()
  local session = H.new()
  agents.hide(session.id)
  agents.toggle()
  eq(agents.current(), session)
  eq(window.visible(session), true)
  eq(#agents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["toggle shows the sole session even when it is visible in another tab"] = function()
  local original = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_win(original)

  agents.toggle()

  eq(agents.current(), session)
  eq(window.visible(session), true)
  eq(#agents.sessions(), 1)
  eq(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["toggle opens the session picker when several sessions are hidden"] = function()
  local first = H.new()
  local second = H.new()
  agents.hide(first.id)
  agents.hide(second.id)
  local picked = capture_picker()
  agents.toggle()
  eq(#picked().items, 2)
  eq(agents.current(), nil)
  eq(window.visible(first), false)
  eq(window.visible(second), false)
  eq(#agents.sessions(), 2)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["toggle opens the session picker when multiple sessions are visible only in another tab"] = function()
  local original = vim.api.nvim_get_current_win()
  local first = H.new({ layout = "tabnew" })
  local second = H.new()
  local elsewhere = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(original)
  local picked = capture_picker()

  agents.toggle()

  eq(#picked().items, 2)
  eq(vim.api.nvim_get_current_win(), original)
  eq(window.visible(first, elsewhere), true)
  eq(window.visible(second, elsewhere), true)
  eq(#agents.sessions(), 2)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["pick always opens a picker even for one session"] = function()
  local session = H.new()
  local picked = capture_picker()
  agents.pick()
  eq(#picked().items, 1)
  eq(picked().items[1].data.id, session.id)
end

T["pick falls through to the tool picker when empty"] = function()
  local picked = capture_picker()
  agents.pick()
  local names = vim.tbl_map(
    ---@param item agents.PickerItem<agents.Tool>
    ---@return string
    function(item)
      return item.data.name
    end,
    picked().items
  )
  eq(vim.tbl_contains(names, "cat"), true)
end

return T
