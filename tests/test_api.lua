local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local window = require("agents.window")
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })
local eq = test.expect.equality

local function capture_picker()
  local spec
  require("agents.config").get().picker = function(value)
    spec = value
  end
  return function()
    return spec
  end
end

T["toggle hides the session under the cursor"] = function()
  H.new()
  local session = H.new()
  agents.toggle()
  eq(window.visible(session), false)
end

T["toggle with no sessions opens the tool picker"] = function()
  local picked = capture_picker()
  agents.toggle()
  eq(picked() ~= nil, true)
  eq(#agents.sessions(), 0)
end

T["toggle focuses the sole visible session in this tab"] = function()
  local original = vim.api.nvim_get_current_win()
  local here = H.new()
  H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_win(original)
  agents.toggle()
  eq(agents.current(), here)
end

T["toggle shows a sole hidden session"] = function()
  local session = H.new()
  agents.hide(session.id)
  agents.toggle()
  eq(agents.current(), session)
end

T["toggle opens the session picker when several candidates remain"] = function()
  local original = vim.api.nvim_get_current_win()
  H.new()
  H.new()
  vim.api.nvim_set_current_win(original)
  local picked = capture_picker()
  agents.toggle()
  eq(#picked().items, 2)
  eq(agents.current(), nil)
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
  local names = vim.tbl_map(function(item)
    return item.data.name
  end, picked().items)
  eq(vim.tbl_contains(names, "cat"), true)
end

return T
