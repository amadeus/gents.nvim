local test = require("mini.test")
local H = require("tests.helpers")
local context = require("gents.context")
local providers = require("gents.providers")
local eq = test.expect.equality
local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      vim.cmd("messages clear")
    end,
    post_case = function()
      H.reset()
      vim.cmd("messages clear")
    end,
  },
})

---@param name string
---@param ctx? gents.Context
---@return gents.Part[]?
local function render(name, ctx)
  return assert(providers.get(name)).render(ctx or context.capture())
end

T["terminal provider omits ordinary buffers"] = function()
  eq(render("terminal"), nil)
end

T["buffer provider reads the captured checkhealth buffer"] = function()
  vim.cmd("checkhealth gents")
  local ctx = context.capture()
  eq(vim.bo[ctx.buf].filetype, "checkhealth")
  local expected = table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n")
  eq(expected:find("gents", 1, true) ~= nil, true)
  vim.cmd("new")
  eq(render("buffer", ctx), { { code = expected, ft = "checkhealth" } })
end

---@return gents.Context
local function terminal()
  local job = vim.fn.jobstart({
    "sh",
    "-c",
    [[i=1; while [ "$i" -le 1250 ]; do printf 'line %03d\n' "$i"; i=$((i + 1)); done; printf '   \n\n'; exec cat]],
  }, { term = true })
  assert(job > 0)
  local ctx = context.capture()
  H.wait(function()
    return table
      .concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n")
      :find("line 1250", 1, true) ~= nil
  end)
  return ctx
end

T["terminal provider trims padding and defaults to the last 1000 lines"] = function()
  local ctx = terminal()
  local parts = assert(render("terminal", ctx))
  local code = assert(parts[1].code)
  local lines = vim.split(code, "\n", { plain = true })
  eq(#lines, 1000)
  eq(lines[1], "line 251")
  eq(lines[#lines], "line 1250")
  eq(parts[1].ft, "text")
end

T["terminal limits vary per call without changing the registered default"] = function()
  local ctx = terminal()
  vim.cmd("new")
  eq(providers.terminal(ctx, 2), { { code = "line 1249\nline 1250", ft = "text" } })
  local parts = assert(require("gents.render").resolve({
    function(captured)
      return providers.terminal(captured, 1)
    end,
  }, ctx))
  eq(parts, { { code = "line 1250", ft = "text" } })
  eq(#vim.split(assert(assert(render("terminal", ctx))[1].code), "\n"), 1000)
end

T["terminal helper reads session buffers"] = function()
  H.new({ cmd = { "sh", "-c", "printf 'session output\\n'; exec cat" } })
  local ctx = context.capture()
  H.wait(function()
    return providers.terminal(ctx, 1) ~= nil
  end)
  eq(providers.terminal(ctx, 1), { { code = "session output", ft = "text" } })
end

T["an empty terminal omits context and invalid limits fail clearly"] = function()
  local job = vim.fn.jobstart({ "cat" }, { term = true })
  assert(job > 0)
  local ctx = context.capture()
  eq(render("terminal", ctx), nil)
  for _, limit in ipairs({ 0, -1 }) do
    test.expect.error(function()
      providers.terminal(ctx, limit)
    end, "positive integer")
  end
end

T["messages omit empty history and preserve recorded text"] = function()
  eq(render("messages"), nil)
  vim.api.nvim_echo({ { "first message" } }, true, {})
  vim.api.nvim_echo({ { "second message" } }, true, {})
  eq(render("messages"), { { text = "first message\nsecond message" } })
  vim.cmd("messages clear")
  eq(render("messages"), nil)
end

T["help context picker"] = test.new_set({ parametrize = { { false }, { true } } }, {
  ---@param selected boolean
  ["offers file and line references in provider order"] = function(selected)
    ---@type gents.PickerSpec<gents.Part[]>?
    local received
    require("gents").setup({
      ---@param spec gents.PickerSpec<gents.Part[]>
      picker = function(spec)
        received = spec
      end,
    })
    vim.cmd.help("help-writing")
    local path = vim.api.nvim_buf_get_name(0)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.cmd("messages clear")
    if selected then
      vim.cmd.normal({ args = { "Vjj" }, bang = true })
      require("gents").send()
    else
      vim.cmd("Gents send")
    end
    local spec = assert(received)
    eq(spec.title, "Gents: Send Context")
    ---@type string[]
    local names = {}
    ---@type table<string, string>
    local previews = {}
    for _, item in ipairs(spec.items) do
      local name = assert(item.text:match("^%S+"))
      names[#names + 1] = name
      previews[name] = item.preview
    end
    local expected = selected and { "line", "selection", "file", "buffer" }
      or { "line", "file", "buffer" }
    eq(vim.list_slice(names, 1, #expected), expected)
    eq(previews.file, "@" .. path)
    eq(previews.line, "@" .. path .. ":" .. row .. (selected and ("-" .. (row + 2)) or ""))
    eq(previews.help, nil)
    eq(assert(previews.buffer):find("Writing help files", 1, true) ~= nil, true)
    eq(previews.selection ~= nil, selected)
  end,
})

T["context picker offers health output through buffer without a duplicate provider"] = function()
  ---@type gents.PickerSpec<gents.Part[]>?
  local received
  require("gents").setup({
    ---@param spec gents.PickerSpec<gents.Part[]>
    picker = function(spec)
      received = spec
    end,
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "health contents" })
  vim.bo.filetype = "checkhealth"
  require("gents").send()
  local spec = assert(received)
  ---@type table<string, string>
  local previews = {}
  for _, item in ipairs(spec.items) do
    previews[assert(item.text:match("^%S+"))] = item.preview
  end
  eq(previews.buffer, "```checkhealth\nhealth contents\n```")
  eq(previews.checkhealth, nil)
  eq(previews.help, nil)
  eq(previews.terminal, nil)
end

return T
