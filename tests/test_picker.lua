local test = require("mini.test")
local H = require("tests.helpers")
local picker = require("agents.picker")
local original_select, original_open, original_notify = vim.ui.select, vim.ui.open, vim.notify
local T = test.new_set({
  hooks = {
    pre_case = H.reset,
    post_case = function()
      vim.ui.select, vim.ui.open, vim.notify = original_select, original_open, original_notify
      H.reset()
    end,
  },
})

local function find_tool(spec, name)
  for _, item in ipairs(spec.items) do
    if item.data.name == name then
      return item
    end
  end
end

T["default adapter formats items and runs only the default action"] = function()
  local selected
  local item = { text = "First item", data = 1 }
  vim.ui.select = function(items, opts, callback)
    test.expect.equality(items, { item })
    test.expect.equality(opts.prompt, "Test picker")
    test.expect.equality(opts.format_item(item), item.text)
    callback(item)
  end
  picker.open({
    title = "Test picker",
    items = { item },
    default = "choose",
    actions = {
      choose = function(value)
        selected = value
      end,
      other = function()
        error("unexpected action")
      end,
    },
  })
  test.expect.equality(selected, item)
end

T["cancelling the default picker does nothing"] = function()
  vim.ui.select = function(_, _, callback)
    callback(nil)
  end
  picker.open({
    title = "Test picker",
    items = { { text = "First item", data = 1 } },
    default = "choose",
    actions = {
      choose = function()
        error("unexpected action")
      end,
    },
  })
end

T["configured adapter receives the complete spec unchanged"] = function()
  local received
  require("agents").setup({
    picker = function(spec)
      received = spec
    end,
  })
  local spec = {
    title = "Test picker",
    items = { { text = "Item", data = 1 } },
    default = "choose",
    actions = { choose = function() end, other = function() end },
  }
  picker.open(spec)
  test.expect.equality(rawequal(received, spec), true)
end

T["tools use the default adapter and launch the selected tool"] = function()
  vim.ui.select = function(items, _, callback)
    callback(find_tool({ items = items }, "cat"))
  end
  local session
  picker.tools(function(tool)
    session = require("agents").new(tool.name)
  end)
  test.expect.equality(session.tool.name, "cat")
  test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["missing tools are annotated and selection reports the install URL"] = function()
  local received
  require("agents").setup({
    tools = {
      missing = { cmd = { "/__agents_missing_executable__" }, url = "https://example.com/install" },
      ignored = { cmd = { "cat" }, enabled = false },
    },
    picker = function(spec)
      received = spec
    end,
  })
  local notification, opened
  vim.notify = function(message, level)
    notification = { message, level }
  end
  vim.ui.open = function(url)
    opened = url
  end
  picker.tools(function()
    error("missing tool must not launch")
  end)

  test.expect.equality(received.default, "new")
  test.expect.equality(type(received.actions.new), "function")
  test.expect.equality(find_tool(received, "ignored"), nil)
  local missing = find_tool(received, "missing")
  test.expect.equality(missing.hl, "Comment")
  test.expect.equality(missing.text, "missing [not installed]")
  received.actions.new(missing)
  test.expect.equality(notification, {
    "agents.nvim: executable not found: /__agents_missing_executable__",
    vim.log.levels.ERROR,
  })
  test.expect.equality(opened, "https://example.com/install")
end

T["tool selection restores its invoking window"] = function()
  local callback, items
  local origin = vim.api.nvim_get_current_win()
  vim.ui.select = function(values, _, on_choice)
    items, callback = values, on_choice
  end
  local session
  picker.tools(function(tool)
    session = require("agents").new(tool.name, { layout = "current" })
  end)
  vim.cmd("new")
  callback(find_tool({ items = items }, "cat"))
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
  test.expect.equality(vim.api.nvim_win_get_buf(origin), session.buf)
end

T["tool selection reports a closed invoking window without launching"] = function()
  local callback, items, notified
  local origin = vim.api.nvim_get_current_win()
  vim.ui.select = function(values, _, on_choice)
    items, callback = values, on_choice
  end
  vim.notify = function(message)
    notified = message
  end
  picker.tools(function()
    error("unexpected launch")
  end)
  vim.cmd("new")
  vim.api.nvim_win_close(origin, true)
  callback(find_tool({ items = items }, "cat"))
  test.expect.equality(
    notified,
    "agents.nvim: the window that opened the tool picker no longer exists"
  )
  test.expect.equality(#require("agents").sessions(), 0)
end

T["session rows prefer this tab and show state cwd and changed argv"] = function()
  require("agents").setup({ tools = { cat = { cmd = { "cat" } }, sh = { cmd = { "sh", "-c" } } } })
  local elsewhere = H.new()
  local hidden = H.new({ layout = "tabnew" })
  vim.cmd("new")
  require("agents").hide(hidden.id)
  local visible = H.new()
  local exited = require("agents").new("sh", { args = { "exit 7" } })
  test.expect.equality(
    vim.wait(1000, function()
      return exited.state == "exited"
    end),
    true
  )

  local selected
  vim.ui.select = function(items, opts, callback)
    test.expect.equality(
      vim.tbl_map(function(item)
        return item.data.id
      end, items),
      { visible.id, exited.id, hidden.id, elsewhere.id }
    )
    test.expect.equality(items[1].text, visible.label .. "  [visible]  " .. visible.cwd)
    test.expect.equality(
      items[2].text,
      exited.label .. "  [exited]  " .. exited.cwd .. "  sh -c exit 7"
    )
    test.expect.equality(items[3].text, hidden.label .. "  [hidden]  " .. hidden.cwd)
    test.expect.equality(items[4].text, elsewhere.label .. "  [visible]  " .. elsewhere.cwd)
    test.expect.equality(opts.format_item(items[1]), items[1].text)
    callback(items[3])
  end
  picker.sessions(require("agents").sessions(), function(session)
    selected = session
  end)
  test.expect.equality(selected, hidden)
end

T["session picker ignores a session closed while it was open"] = function()
  local session = H.new()
  local callback, item
  vim.ui.select = function(items, _, on_choice)
    item, callback = items[1], on_choice
  end
  picker.sessions({ session }, function()
    error("closed session must not be selected")
  end)
  require("agents").close(session.id)
  callback(item)
end

T["session selection reports a closed invoking window without showing"] = function()
  local session = H.new()
  require("agents").hide(session.id)
  local origin = vim.api.nvim_get_current_win()
  local callback, item, notified
  vim.ui.select = function(items, _, on_choice)
    item, callback = items[1], on_choice
  end
  vim.notify = function(message)
    notified = message
  end
  picker.sessions({ session }, function(selected)
    require("agents").show(selected.id, { layout = "current" })
  end)
  vim.cmd("new")
  local unrelated = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_close(origin, true)
  callback(item)
  test.expect.equality(
    notified,
    "agents.nvim: the window that opened the session picker no longer exists"
  )
  test.expect.equality(vim.api.nvim_get_current_buf(), unrelated)
  test.expect.equality(vim.fn.win_findbuf(session.buf), {})
end

T["a native view in another tab ranks after hidden sessions from this tab"] = function()
  local origin = vim.api.nvim_get_current_win()
  local elsewhere, hidden = H.new(), H.new()
  require("agents").hide(elsewhere.id)
  require("agents").hide(hidden.id)
  vim.cmd.tabnew()
  vim.api.nvim_win_set_buf(0, elsewhere.buf)
  vim.api.nvim_set_current_win(origin)
  local spec
  require("agents.config").get().picker = function(value)
    spec = value
  end
  require("agents").pick()
  test.expect.equality(
    { spec.items[1].data.id, spec.items[2].data.id },
    { hidden.id, elsewhere.id }
  )
end

return T
