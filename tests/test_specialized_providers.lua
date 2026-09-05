local test = require("mini.test")
local H = require("tests.helpers")
local context = require("agents.context")
local providers = require("agents.providers")
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
---@param ctx? agents.Context
---@return agents.Part[]?
local function render(name, ctx)
  return assert(providers.get(name)).render(ctx or context.capture())
end

T["specialized buffer providers omit ordinary buffers"] = function()
  for _, name in ipairs({ "help", "checkhealth", "terminal" }) do
    eq(render(name), nil)
  end
end

T["health provider reads the captured checkhealth buffer"] = function()
  vim.cmd("checkhealth agents")
  local ctx = context.capture()
  eq(vim.bo[ctx.buf].filetype, "checkhealth")
  local expected = table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n")
  eq(expected:find("agents", 1, true) ~= nil, true)
  vim.cmd("new")
  eq(render("checkhealth", ctx), { { code = expected, ft = "checkhealth" } })
end

---@return agents.Context
local function terminal()
  local job = vim.fn.jobstart({
    "sh",
    "-c",
    [[i=1; while [ "$i" -le 250 ]; do printf 'line %03d\n' "$i"; i=$((i + 1)); done; printf '   \n\n'; exec cat]],
  }, { term = true })
  assert(job > 0)
  local ctx = context.capture()
  H.wait(function()
    return table
      .concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n")
      :find("line 250", 1, true) ~= nil
  end)
  return ctx
end

T["terminal provider trims padding and defaults to the last 200 lines"] = function()
  local ctx = terminal()
  local parts = assert(render("terminal", ctx))
  local code = assert(parts[1].code)
  local lines = vim.split(code, "\n", { plain = true })
  eq(#lines, 200)
  eq(lines[1], "line 051")
  eq(lines[#lines], "line 250")
  eq(parts[1].ft, "text")
end

T["terminal limits vary per call without changing the registered default"] = function()
  local ctx = terminal()
  vim.cmd("new")
  eq(providers.terminal(ctx, 2), { { code = "line 249\nline 250", ft = "text" } })
  local parts = assert(require("agents.render").resolve({
    function(captured)
      return providers.terminal(captured, 1)
    end,
  }, ctx))
  eq(parts, { { code = "line 250", ft = "text" } })
  eq(#vim.split(assert(assert(render("terminal", ctx))[1].code), "\n"), 200)
end

T["terminal provider accepts session buffers supplied as source context"] = function()
  local session = H.new({ cmd = { "sh", "-c", "printf 'session output\\n'; exec cat" } })
  -- Ordinary send capture intentionally skips the focused agent terminal.
  ---@type agents.Context
  local ctx = {
    win = vim.api.nvim_get_current_win(),
    buf = session.buf,
    cwd = session.cwd,
    cursor = { 1, 0 },
  }
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

T["context picker shows applicable specialized entries with previews"] = function()
  ---@type agents.PickerSpec<agents.Part[]>?
  local received
  require("agents").setup({
    ---@param spec agents.PickerSpec<agents.Part[]>
    picker = function(spec)
      received = spec
    end,
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "health contents" })
  vim.bo.filetype = "checkhealth"
  require("agents").send()
  local spec = assert(received)
  ---@type table<string, string>
  local previews = {}
  for _, item in ipairs(spec.items) do
    previews[assert(item.text:match("^%S+"))] = item.preview
  end
  eq(previews.checkhealth, "```checkhealth\nhealth contents\n```")
  eq(previews.help, nil)
  eq(previews.terminal, nil)
end

return T
