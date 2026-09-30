local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

---@param keys string
local function input(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

---@param setup? gents.SetupOptions
local function enable(setup)
  local opts = setup or {}
  opts.extend_gf = true
  opts.tools = opts.tools or {}
  opts.tools.cat = opts.tools.cat or { cmd = { "cat" } }
  gents.setup(opts)
  H.wait(function()
    return vim.fn.maparg("gf", "n", false, true).desc
      == "Gents: follow conversation reference or original gf"
  end)
end

local function text(value)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { value, "next", "last" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

---@param mode string
---@param lhs string
local function restore(mode, lhs)
  local original = vim.fn.maparg(lhs, mode, false, true)
  test.finally(function()
    pcall(vim.keymap.del, mode, lhs)
    if next(original) ~= nil and original.buffer == 0 then
      vim.fn.mapset(mode, false, original)
    end
  end)
end

T["default leaves all maps untouched and rejects invalid setting values"] = function()
  local callback = function() end
  vim.keymap.set("n", "gf", callback, { buffer = true })
  gents.setup()
  eq(vim.fn.maparg("gf", "n", false, true).callback, callback)
  eq(require("gents.config").get().extend_gf, false)
end

T["native path search counts includeexpr and suffixes are preserved"] = function()
  local directory = vim.fn.tempname()
  vim.fn.mkdir(directory .. "/one", "p")
  vim.fn.mkdir(directory .. "/two", "p")
  local first = directory .. "/one/target.lua"
  local second = directory .. "/two/target.lua"
  vim.fn.writefile({ "first" }, first)
  vim.fn.writefile({ "second" }, second)
  test.finally(function()
    vim.fn.delete(directory, "rf")
  end)
  text("package:target")
  local isfname = vim.o.isfname
  vim.opt.isfname:append(":")
  test.finally(function()
    vim.o.isfname = isfname
  end)
  vim.bo.path = directory .. "/one," .. directory .. "/two"
  vim.bo.suffixesadd = ".lua"
  vim.bo.includeexpr = [[substitute(v:fname, '^package:', '', '')]]
  enable()
  input("2gf")
  eq(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)), vim.uv.fs_realpath(second))
end

T["effective mappings"] = test.new_set({ parametrize = { { false }, { true } } }, {
  ---@param local_map boolean
  ["callback receives counts and is restored with its original scope and flags"] = function(
    local_map
  )
    restore("n", "gf")
    local seen = 0
    local function callback()
      seen = vim.v.count
    end
    vim.keymap.set("n", "gf", callback, { buffer = local_map, silent = true, nowait = true })
    local original = vim.fn.maparg("gf", "n", false, true)
    text("ordinary")
    enable()
    input("3gf")
    eq(seen, 3)
    gents.setup({ extend_gf = false })
    eq(vim.fn.maparg("gf", "n", false, true), original)
    eq(vim.fn.mapcheck("<Plug>(gents-gf-", "n"), "")
  end,
})

T["string and expression mappings"] = test.new_set({
  parametrize = { { false, false }, { true, false }, { false, true }, { true, true } },
}, {
  ---@param expr boolean
  ---@param remap boolean
  ["delegate through Neovim's mapping engine"] = function(expr, remap)
    local hits = 0
    vim.keymap.set("n", "j", function()
      hits = hits + 1
    end, { buffer = true })
    ---@type string|fun(): string
    local rhs = expr and function()
      return "j"
    end or "j"
    vim.keymap.set("n", "gf", rhs, { buffer = true, expr = expr, remap = remap })
    text("ordinary")
    enable()
    input("gf")
    eq(hits, remap and 1 or 0)
    eq(vim.api.nvim_win_get_cursor(0)[1], remap and 1 or 2)
  end,
})

T["script-local expression and script remapping retain their defining SID"] = function()
  local script = vim.fn.tempname() .. ".vim"
  vim.fn.writefile({
    "function! s:Move() abort",
    "  return 'j'",
    "endfunction",
    "nnoremap <expr> <buffer> gf <SID>Move()",
    "nnoremap <buffer> <SID>move j",
  }, script)
  test.finally(function()
    vim.fn.delete(script)
  end)
  vim.cmd.source(script)
  text("ordinary")
  local original = vim.fn.maparg("gf", "n", false, true)
  enable()
  input("gf")
  eq(vim.api.nvim_win_get_cursor(0)[1], 2)
  gents.setup()
  eq(vim.fn.maparg("gf", "n", false, true), original)
  vim.fn.writefile({ "nmap <script> <buffer> gf <SID>move" }, script, "a")
  vim.cmd.source(script)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  enable()
  input("gf")
  eq(vim.api.nvim_win_get_cursor(0)[1], 2)
end

T["references open once and recognized errors do not execute the fallback"] = function()
  local origin = vim.api.nvim_get_current_win()
  local hits = 0
  vim.keymap.set("n", "gf", function()
    hits = hits + 1
  end, { buffer = true })
  text("custom:[literal id]")
  enable({
    tools = {
      custom = {
        cmd = { "sh", "-c", "exec cat", "custom" },
        resume = function(identifier)
          return { identifier }
        end,
      },
    },
  })
  input("gf")
  local session = assert(gents.current())
  eq(session.resume, "literal id")
  eq(#gents.sessions(), 1)
  eq(hits, 0)
  vim.api.nvim_set_current_win(origin)
  text("custom:[unclosed")
  input("gf")
  eq(hits, 0)
  eq(#gents.sessions(), 1)
  text("q:saved")
  input("gf")
  eq(hits, 0)
  eq(#gents.sessions(), 1)
  text("unknown:saved")
  input("gf")
  eq(hits, 1)
end

T["later local and global replacements remain effective, including repeated setup"] = function()
  restore("n", "gf")
  text("ordinary")
  enable()
  local hits = 0
  local function global()
    hits = vim.v.count
  end
  vim.keymap.set("n", "gf", global)
  input("4gf")
  eq(hits, 4)
  eq(vim.fn.maparg("gf", "n", false, true).callback, global)
  gents.setup({ extend_gf = true })
  vim.wait(10)
  eq(vim.fn.maparg("gf", "n", false, true).callback, global)
  gents.setup()
  enable()
  local function replacement()
    hits = 9
  end
  vim.keymap.set("n", "gf", replacement, { buffer = true })
  require("gents.gf").attach(vim.api.nvim_get_current_buf())
  gents.setup({ extend_gf = true })
  vim.wait(10)
  eq(vim.fn.maparg("gf", "n", false, true).callback, replacement)
  input("gf")
  eq(hits, 9)
  gents.setup()
  eq(vim.fn.maparg("gf", "n", false, true).callback, replacement)
end

T["scheduled entry wraps maps installed later in the same event and cleans up on disable"] = function()
  local group = vim.api.nvim_create_augroup("GentsGFTest", { clear = true })
  test.finally(function()
    vim.api.nvim_del_augroup_by_id(group)
  end)
  enable()
  local hits = 0
  local function callback()
    hits = hits + 1
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "gents_gf_test",
    callback = function(ev)
      vim.keymap.set("n", "gf", callback, { buffer = ev.buf })
    end,
  })
  vim.cmd.enew()
  text("ordinary")
  vim.bo.filetype = "gents_gf_test"
  H.wait(function()
    return vim.fn.maparg("gf", "n", false, true).callback ~= callback
  end)
  input("gf")
  eq(hits, 1)
  gents.setup()
  eq(vim.fn.maparg("gf", "n", false, true).callback, callback)
end

T["repeated setup preserves a global replacement before the wrapper is invoked"] = function()
  restore("n", "gf")
  enable()
  local function replacement() end
  vim.keymap.set("n", "gf", replacement)
  gents.setup({ extend_gf = true })
  vim.wait(10)
  eq(vim.fn.maparg("gf", "n", false, true).callback, replacement)
end

T["existing hidden buffers are wrapped without repeatedly queuing temporary entries"] = function()
  local buffers = { vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true) }
  local group = vim.api.nvim_create_augroup("GentsGFEntriesTest", { clear = true })
  local count = 0
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      count = count + 1
    end,
  })
  test.finally(function()
    vim.api.nvim_del_augroup_by_id(group)
  end)
  enable()
  H.wait(function()
    for _, buf in ipairs(buffers) do
      local found = false
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs == "gf" then
          found = true
        end
      end
      if not found then
        return false
      end
    end
    return true
  end)
  local settled = count
  vim.wait(20)
  eq(count, settled)
end

T["visual gf, gF, window variants, and terminal input are untouched"] = function()
  for _, lhs in ipairs({ "gF", "<C-w>f", "<C-w>gf" }) do
    vim.keymap.set("n", lhs, "j", { buffer = true })
  end
  vim.keymap.set("x", "gf", "j", { buffer = true })
  local before = vim.api.nvim_buf_get_keymap(0, "n")
  local visual = vim.fn.maparg("gf", "x", false, true)
  enable()
  for _, map in ipairs(before) do
    eq(vim.fn.maparg(assert(map.lhs), "n", false, true).rhs, map.rhs)
  end
  eq(vim.fn.maparg("gf", "x", false, true), visual)
  local session = H.new()
  H.wait(function()
    return vim.fn.maparg("gf", "n", false, true).desc ~= nil
  end)
  eq(vim.api.nvim_buf_get_keymap(session.buf, "t"), {})
end

return T
