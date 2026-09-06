local test = require("mini.test")
local H = require("tests.helpers")
local context = require("agents.context")
local eq = test.expect.equality
local original_selection = vim.o.selection
local original_virtualedit = vim.o.virtualedit
---@type string
local temp_dir

local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      temp_dir = vim.fn.tempname()
      vim.fn.mkdir(temp_dir, "p")
      temp_dir = assert(vim.uv.fs_realpath(temp_dir))
    end,
    post_case = function()
      vim.cmd.normal({ args = { "\27" }, bang = true })
      vim.o.selection = original_selection
      vim.o.virtualedit = original_virtualedit
      H.reset()
      vim.fn.delete(temp_dir, "d")
    end,
  },
})

---@param lines string[]
---@param mode string
---@param first [integer, integer]
---@param last [integer, integer]
---@return agents.Context
local function visual(lines, mode, first, last)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, first)
  vim.cmd.normal({ args = { mode }, bang = true })
  vim.api.nvim_win_set_cursor(0, last)
  return context.capture()
end

T["normal source preserves its window buffer cwd and cursor"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second" })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  vim.cmd.lcd(temp_dir)
  local source = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  eq(context.capture(), { win = source, buf = buf, cwd = temp_dir, cursor = { 2, 3 } })
  eq(vim.api.nvim_get_current_win(), source)
end

T["session source prefers previous window with its own cwd"] = function()
  vim.cmd.lcd(temp_dir)
  local source = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  H.new()
  local terminal = vim.api.nvim_get_current_win()
  vim.cmd.lcd("/")
  local ctx = context.capture()
  eq({ ctx.win, ctx.buf, ctx.cwd }, { source, buf, temp_dir })
  eq(vim.api.nvim_get_current_win(), terminal)
end

T["session source falls back past a previous session in this tab"] = function()
  local source = vim.api.nvim_get_current_win()
  H.new()
  H.new()
  eq(context.capture().win, source)
end

T["another tab is not a source when this tab contains only sessions"] = function()
  H.new({ layout = "tabnew" })
  test.expect.error(context.capture, "no source window available in this tab")
end

T["character selection normalizes backwards Unicode endpoints"] = function()
  local ctx = visual({ "abc", "αβγ" }, "v", { 2, 2 }, { 1, 1 })
  eq(ctx.range, { kind = "char", start = { 1, 1 }, finish = { 2, 3 } })
  eq(context.selection(ctx), { "bc", "αβ" })
end

T["exclusive selection captures the included endpoint"] = function()
  vim.o.selection = "exclusive"
  local ctx = visual({ "αβγ" }, "v", { 1, 0 }, { 1, 4 })
  eq(ctx.range, { kind = "char", start = { 1, 0 }, finish = { 1, 3 } })
  eq(context.selection(ctx), { "αβ" })
end

T["line selection and explicit Ex ranges include complete lines"] = function()
  local ctx = visual({ "alpha", "  beta", "last" }, "V", { 2, 4 }, { 1, 2 })
  eq(ctx.range, { kind = "line", start = { 1, 0 }, finish = { 2, 0 } })
  eq(context.selection(ctx), { "alpha", "  beta" })
  vim.cmd.normal({ args = { "\27" }, bang = true })
  local ranged = context.capture({ line1 = 2, line2 = 3 })
  eq(ranged.range, { kind = "line", start = { 2, 0 }, finish = { 3, 0 } })
  eq(context.selection(ranged), { "  beta", "last" })
end

T["block selection preserves screen columns across tabs and Unicode"] = function()
  vim.bo.tabstop = 4
  local ctx = visual({ "abcd", "\txyz", "αβγδ" }, "\22", { 1, 1 }, { 3, 4 })
  eq(ctx.range, { kind = "block", start = { 1, 1 }, finish = { 3, 5 } })
  eq(context.selection(ctx), { "bc", "  ", "βγ" })
end

T["block selection to dollar extends to each line end"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "xy", "123456789" })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd.normal({ args = { "\22" }, bang = true })
  vim.cmd.normal({ args = { "2j$" }, bang = true })
  eq(context.selection(context.capture()), { "cdef", "", "3456789" })
end

T["selection text stays captured after mode option and buffer changes"] = function()
  local ctx = visual({ "abc", "def" }, "v", { 1, 1 }, { 2, 1 })
  vim.cmd.normal({ args = { "\27" }, bang = true })
  vim.o.selection = "exclusive"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "replacement" })
  local lines = assert(context.selection(ctx))
  eq(lines, { "bc", "de" })
  lines[1] = "mutated"
  eq(context.selection(ctx), { "bc", "de" })
  eq(context.capture().range, nil)
end

T["normal mode does not reuse stale visual marks"] = function()
  visual({ "abc" }, "v", { 1, 0 }, { 1, 1 })
  vim.cmd.normal({ args = { "\27" }, bang = true })
  local ctx = context.capture()
  eq(ctx.range, nil)
  eq(context.selection(ctx), nil)
end

return T
