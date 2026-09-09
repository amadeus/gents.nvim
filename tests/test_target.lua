local test = require("mini.test")
local H = require("tests.helpers")
local target = require("gents.target")
local original_select = vim.ui.select

---@param select fun<T>(items: T[], opts: vim.ui.select.Opts, on_choice: fun(item: T?, idx?: integer))
local function set_select(select)
  vim.ui.select = select
end

local T = test.new_set({
  hooks = {
    pre_case = H.reset,
    post_case = function()
      set_select(original_select)
      H.reset()
    end,
  },
})

T["explicit ids and labels override the current session"] = function()
  local first = H.new()
  local second = H.new()
  ---@type gents.Session?
  local selected
  local result = target.with(first.id, function(session)
    selected = session
    return "result"
  end)
  test.expect.equality(selected, first)
  test.expect.equality(result, "result")

  target.with(second.label, function(session)
    selected = session
  end)
  test.expect.equality(selected, second)
end

T["current session wins when several sessions are visible"] = function()
  H.new()
  local current = H.new()
  test.expect.equality(
    target.with(nil, function(session)
      return session.id
    end),
    current.id
  )
end

T["one visible session still opens the picker when sessions exist elsewhere"] = function()
  local here = H.new()
  local tab = vim.api.nvim_get_current_tabpage()
  local elsewhere = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_tabpage(tab)
  vim.cmd("new")
  ---@type integer?
  local selected
  ---@param items gents.PickerItem<gents.Session>[]
  ---@param _ vim.ui.select.Opts
  ---@param callback fun(item: gents.PickerItem<gents.Session>?, idx?: integer)
  set_select(function(items, _, callback)
    test.expect.equality({ items[1].data.id, items[2].data.id }, { here.id, elsewhere.id })
    callback(items[2], 2)
  end)

  test.expect.equality(
    target.with(nil, function(session)
      selected = session.id
    end),
    nil
  )
  test.expect.equality(selected, elsewhere.id)
end

T["one visible session still opens the picker when another session is hidden"] = function()
  local original = vim.api.nvim_get_current_win()
  local visible = H.new()
  local hidden = H.new()
  require("gents").hide(hidden.id)
  vim.api.nvim_set_current_win(original)
  ---@type integer?
  local selected
  ---@param items gents.PickerItem<gents.Session>[]
  ---@param _ vim.ui.select.Opts
  ---@param callback fun(item: gents.PickerItem<gents.Session>?, idx?: integer)
  set_select(function(items, _, callback)
    test.expect.equality({ items[1].data.id, items[2].data.id }, { visible.id, hidden.id })
    callback(items[2], 2)
  end)

  target.with(nil, function(session)
    selected = session.id
  end)
  test.expect.equality(selected, hidden.id)
end

T["a sole hidden session is selected"] = function()
  local session = H.new()
  require("gents").hide(session.id)
  test.expect.equality(
    target.with(nil, function(selected)
      return selected.id
    end),
    session.id
  )
end

T["ambiguous sessions use the picker and return nil"] = function()
  local first = H.new()
  local second = H.new()
  require("gents").hide(first.id)
  require("gents").hide(second.id)
  ---@type gents.Session?
  local selected
  ---@param items gents.PickerItem<gents.Session>[]
  ---@param _ vim.ui.select.Opts
  ---@param callback fun(item: gents.PickerItem<gents.Session>?, idx?: integer)
  set_select(function(items, _, callback)
    test.expect.equality(#items, 2)
    callback(items[2], 2)
  end)
  test.expect.equality(
    target.with(nil, function(session)
      selected = session
      return "ignored"
    end),
    nil
  )
  test.expect.equality(selected, second)
end

T["filters prefer an eligible current session and resolve a sole matching session"] = function()
  local current = H.new()
  local current_win = vim.api.nvim_get_current_win()
  local hidden = H.new()
  require("gents").hide(hidden.id)
  local unrelated = H.new()
  vim.api.nvim_set_current_win(current_win)
  local selected = target.with(function(session)
    return session.id ~= unrelated.id
  end, function(session)
    return session.id
  end)
  test.expect.equality(selected, current.id)

  selected = target.with(function(session)
    return session.id == hidden.id
  end, function(session)
    return session.id
  end)
  test.expect.equality(selected, hidden.id)
end

T["an ambiguous filter only offers matching sessions"] = function()
  local first = H.new()
  local second = H.new()
  local unrelated = H.new()
  ---@type integer?
  local selected
  ---@param items gents.PickerItem<gents.Session>[]
  ---@param _ vim.ui.select.Opts
  ---@param callback fun(item: gents.PickerItem<gents.Session>?, idx?: integer)
  set_select(function(items, _, callback)
    test.expect.equality({ items[1].data.id, items[2].data.id }, { first.id, second.id })
    test.expect.equality(#items, 2)
    callback(items[1], 1)
  end)
  target.with(function(session)
    return session.id ~= unrelated.id
  end, function(session)
    selected = session.id
  end)
  test.expect.equality(selected, first.id)
end

T["no sessions is a no-op and explicit unmatched targets error"] = function()
  local called = false
  local callback = function()
    called = true
  end
  set_select(function()
    error("unexpected picker")
  end)
  test.expect.equality(target.with(nil, callback), nil)
  test.expect.error(function()
    target.with(12345, callback)
  end, "no session matches")
  test.expect.error(function()
    target.with("unknown", callback)
  end, "no session matches")
  test.expect.error(function()
    target.with(function()
      return false
    end, callback)
  end, "no session matches target filter")
  test.expect.error(function()
    -- A table is deliberately outside the public target contract.
    ---@diagnostic disable-next-line: param-type-mismatch
    target.with({}, callback)
  end, "target must be")
  test.expect.equality(called, false)
end

return T
