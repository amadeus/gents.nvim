local test = require("mini.test")
local H = require("tests.helpers")
local providers = require("gents.providers")
local context = require("gents.context")
local eq = test.expect.equality
local namespace = vim.api.nvim_create_namespace("GentsProvidersTest")

local T = test.new_set({
  hooks = {
    pre_case = H.reset,
    post_case = function()
      vim.cmd.normal({ args = { "\27" }, bang = true })
      vim.diagnostic.reset(namespace)
      vim.fn.setqflist({}, "r")
      H.reset()
      vim.fn.setloclist(0, {}, "r")
    end,
  },
})

---@param name string
---@param ctx? gents.Context
---@return gents.Part[]?
local function render(name, ctx)
  return assert(providers.get(name)).render(ctx or context.capture())
end

---@return string
local function named_buffer()
  local path = vim.fn.getcwd() .. "/providers-example.lua"
  vim.api.nvim_buf_set_name(0, path)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local x = 1", "return x" })
  vim.bo.filetype = "lua"
  return path
end

T["registry keeps builtin order and sorts custom names"] = function()
  providers.register("__test_zulu", { desc = "Zulu", render = function() end })
  providers.register("__test_alpha", { desc = "Alpha", render = function() end })
  local names = providers.names()
  eq(vim.list_slice(names, 1, 9), {
    "line",
    "selection",
    "file",
    "buffer",
    "messages",
    "diagnostics",
    "quickfix",
    "locationlist",
    "terminal",
  })
  local custom = vim.list_slice(names, 10)
  local sorted = vim.deepcopy(custom)
  table.sort(sorted)
  eq(custom, sorted)
  eq(assert(providers.get("__test_alpha")).desc, "Alpha")
  eq(providers.get("position"), nil)
  eq(providers.get("checkhealth"), nil)
  eq(providers.get("help"), nil)
  eq(providers.get("missing"), nil)
end

T["registration can replace a builtin"] = function()
  local original = assert(providers.get("file"))
  test.finally(function()
    providers.register("file", original)
  end)
  providers.register("file", {
    desc = "Replacement",
    render = function(ctx)
      return { { text = tostring(ctx.buf) } }
    end,
  })
  eq(render("file"), { { text = tostring(vim.api.nvim_get_current_buf()) } })
end

T["file and line support named files that do not exist yet"] = function()
  local path = named_buffer()
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  eq(render("file"), { { path = path } })
  eq(
    render("line"),
    { { path = path, range = { kind = "line", start = { 2, 0 }, finish = { 2, 0 } } } }
  )
end

T["location providers omit unnamed and non-file buffers"] = function()
  for _, buftype in ipairs({ "", "help" }) do
    vim.bo.buftype = buftype
    for _, name in ipairs({ "file", "line" }) do
      eq(render(name), nil)
    end
  end
  vim.bo.buftype = ""
  named_buffer()
  vim.bo.buftype = "nofile"
  for _, name in ipairs({ "file", "line" }) do
    eq(render(name), nil)
  end
  eq(render("buffer"), { { code = "local x = 1\nreturn x", ft = "lua" } })
end

T["file and line reference captured help files after focus changes"] = function()
  vim.cmd.help("help-writing")
  eq(vim.bo.buftype, "help")
  local path = vim.api.nvim_buf_get_name(0)
  eq(vim.fn.filereadable(path), 1)
  local ctx = context.capture()
  local row = ctx.cursor[1]
  local selected = context.capture({ line1 = row, line2 = row + 2 })
  vim.cmd.new()
  named_buffer()
  eq(render("file", ctx), { { path = path } })
  eq(
    render("line", ctx),
    { { path = path, range = { kind = "line", start = { row, 0 }, finish = { row, 0 } } } }
  )
  eq(render("line", selected), {
    { path = path, range = { kind = "line", start = { row, 0 }, finish = { row + 2, 0 } } },
  })
end

T["line uses selected rows for a character selection"] = function()
  local path = named_buffer()
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.cmd.normal({ args = { "v" }, bang = true })
  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  local ctx = context.capture()
  eq(
    render("line", ctx),
    { { path = path, range = { kind = "line", start = { 1, 0 }, finish = { 2, 0 } } } }
  )
end

T["selection dedents common indentation and retains filetype"] = function()
  eq(render("selection"), nil)
  vim.bo.filetype = "lua"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "  if ready then", "    run()", "  end" })
  eq(
    render("selection", context.capture({ line1 = 1, line2 = 3 })),
    { { code = "if ready then\n  run()\nend", ft = "lua" } }
  )
end

T["selection dedents mixed tabs and spaces without changing alignment"] = function()
  vim.bo.tabstop = 4
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "\tfirst", "  second", "\t  third" })
  eq(
    render("selection", context.capture({ line1 = 1, line2 = 3 })),
    { { code = "  first\nsecond\n    third", ft = "" } }
  )
end

T["providers use captured source after another buffer becomes current"] = function()
  local path = named_buffer()
  local ctx = context.capture()
  vim.cmd.new()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unrelated" })
  eq(render("file", ctx), { { path = path } })
  eq(render("buffer", ctx), { { code = "local x = 1\nreturn x", ft = "lua" } })
end

T["diagnostics use only this buffer and filter char selection columns"] = function()
  named_buffer()
  eq(render("diagnostics"), nil)
  vim.diagnostic.set(namespace, 0, {
    {
      lnum = 0,
      col = 0,
      end_col = 2,
      message = "outside",
      severity = vim.diagnostic.severity.WARN,
    },
    {
      lnum = 0,
      col = 3,
      end_col = 4,
      message = "inside",
      severity = vim.diagnostic.severity.ERROR,
    },
    {
      lnum = 0,
      col = 4,
      end_col = 8,
      message = "overlap",
      severity = vim.diagnostic.severity.INFO,
    },
    { lnum = 1, col = 3, message = "other row" },
  })
  local other = vim.api.nvim_create_buf(false, true)
  vim.diagnostic.set(namespace, other, { { lnum = 0, col = 0, message = "other buffer" } })
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  vim.cmd.normal({ args = { "v" }, bang = true })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  eq(render("diagnostics"), {
    { text = "providers-example.lua:1:4: ERROR: inside\nproviders-example.lua:1:5: INFO: overlap" },
  })
end

T["diagnostics filter block selections per row and handle point diagnostics"] = function()
  named_buffer()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "abcdef" })
  vim.diagnostic.set(namespace, 0, {
    { lnum = 0, col = 1, message = "top point" },
    { lnum = 0, col = 4, message = "top outside" },
    { lnum = 1, col = 0, message = "bottom outside" },
    { lnum = 1, col = 2, message = "bottom point" },
  })
  vim.api.nvim_win_set_cursor(0, { 1, 1 })
  vim.cmd.normal({ args = { "\22" }, bang = true })
  vim.api.nvim_win_set_cursor(0, { 2, 2 })
  eq(render("diagnostics"), {
    {
      text = "providers-example.lua:1:2: ERROR: top point\nproviders-example.lua:2:3: ERROR: bottom point",
    },
  })
end

T["line diagnostics include overlapping multiline ranges but exclude an end at column zero"] = function()
  named_buffer()
  vim.diagnostic.set(namespace, 0, {
    { lnum = 0, col = 0, end_lnum = 1, end_col = 1, message = "overlap" },
    { lnum = 0, col = 1, end_lnum = 1, end_col = 0, message = "before" },
    { lnum = 1, col = 6, message = "point" },
  })
  eq(render("diagnostics", context.capture({ line1 = 2, line2 = 2 })), {
    { text = "providers-example.lua:1:1: ERROR: overlap\nproviders-example.lua:2:7: ERROR: point" },
  })
end

T["quickfix preserves entry order and includes messages without locations"] = function()
  named_buffer()
  eq(render("quickfix"), nil)
  vim.fn.setqflist({
    { bufnr = vim.api.nvim_get_current_buf(), lnum = 2, col = 3, text = "fix this" },
    { text = "summary", valid = false },
  }, "r")
  eq(render("quickfix"), { { text = "providers-example.lua:2:3: fix this\nsummary" } })
end

T["locationlist uses the captured window and keeps all entries in list order"] = function()
  named_buffer()
  eq(render("locationlist"), nil)
  vim.fn.setloclist(0, {
    { bufnr = vim.api.nvim_get_current_buf(), lnum = 2, col = 3, text = "second line" },
    { bufnr = vim.api.nvim_get_current_buf(), lnum = 1, col = 1, text = "first line" },
    { text = "summary", valid = false },
  }, "r")
  local ctx = context.capture({ line1 = 1, line2 = 1 })
  vim.cmd.split()
  eq(vim.api.nvim_get_current_buf(), ctx.buf)
  vim.fn.setloclist(0, { { text = "other window" } }, "r")
  vim.fn.setqflist({ { text = "global quickfix" } }, "r")
  eq(render("locationlist", ctx), {
    {
      text = "providers-example.lua:2:3: second line\nproviders-example.lua:1:1: first line\nsummary",
    },
  })
  eq(render("locationlist"), { { text = "other window" } })
  eq(render("quickfix", ctx), { { text = "global quickfix" } })
  vim.fn.setloclist(ctx.win, {}, "r")
  eq(render("locationlist", ctx), nil)
end

T["locationlist reads the displayed list when invoked in its window"] = function()
  named_buffer()
  vim.fn.setloclist(0, {
    { bufnr = vim.api.nvim_get_current_buf(), lnum = 2, col = 3, text = "fix this" },
  }, "r")
  vim.cmd.lopen()
  eq(vim.bo.buftype, "quickfix")
  eq(render("locationlist"), { { text = "providers-example.lua:2:3: fix this" } })
end

T["diagnostic and quickfix paths preserve literal environment and tilde characters"] = function()
  local original = vim.env.GENTS_TEST_PATH
  test.finally(function()
    vim.env.GENTS_TEST_PATH = original
  end)
  vim.env.GENTS_TEST_PATH = "expanded-incorrectly"
  local name = "~/$GENTS_TEST_PATH.lua"
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/" .. name)
  vim.diagnostic.set(namespace, 0, { { lnum = 0, col = 0, message = "diagnostic" } })
  vim.fn.setqflist(
    { { bufnr = vim.api.nvim_get_current_buf(), lnum = 1, col = 1, text = "quickfix" } },
    "r"
  )
  eq(render("diagnostics"), { { text = name .. ":1:1: ERROR: diagnostic" } })
  eq(render("quickfix"), { { text = name .. ":1:1: quickfix" } })
end

return T
