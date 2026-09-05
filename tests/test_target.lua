local test = require("mini.test")
local H = require("tests.helpers")
local target = require("agents.target")
local original_select = vim.ui.select
local T = test.new_set({
  hooks = {
    pre_case = H.reset,
    post_case = function()
      vim.ui.select = original_select
      H.reset()
    end,
  },
})

T["explicit ids and labels override the current session"] = function()
  local first = H.new()
  local second = H.new()
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

T["one session visible in this tab wins over sessions elsewhere"] = function()
  local here = H.new()
  local tab = vim.api.nvim_get_current_tabpage()
  H.new({ layout = "tabnew" })
  H.new()
  vim.api.nvim_set_current_tabpage(tab)
  vim.cmd("new")

  test.expect.equality(
    target.with(nil, function(session)
      return session.id
    end),
    here.id
  )
end

T["a sole hidden session is selected"] = function()
  local session = H.new()
  require("agents").hide(session.id)
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
  require("agents").hide(first.id)
  require("agents").hide(second.id)
  local selected
  vim.ui.select = function(items, _, callback)
    test.expect.equality(#items, 2)
    callback(items[2])
  end
  test.expect.equality(
    target.with(nil, function(session)
      selected = session
      return "ignored"
    end),
    nil
  )
  test.expect.equality(selected, second)
end

T["filters constrain current and visible resolution"] = function()
  local visible = H.new()
  local hidden = H.new()
  require("agents").hide(hidden.id)
  local unrelated = H.new()
  local selected = target.with(function(session)
    return session.id ~= unrelated.id
  end, function(session)
    return session.id
  end)
  test.expect.equality(selected, visible.id)

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
  local selected
  vim.ui.select = function(items, _, callback)
    test.expect.equality({ items[1].data.id, items[2].data.id }, { first.id, second.id })
    test.expect.equality(#items, 2)
    callback(items[1])
  end
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
  vim.ui.select = function()
    error("unexpected picker")
  end
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
    target.with({}, callback)
  end, "target must be")
  test.expect.equality(called, false)
end

return T
