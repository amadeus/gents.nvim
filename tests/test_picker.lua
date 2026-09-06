local test = require("mini.test")
local H = require("tests.helpers")
local picker = require("agents.picker")
local original_select, original_open, original_notify = vim.ui.select, vim.ui.open, vim.notify
local original_input = vim.ui.input
local T = test.new_set({
  hooks = {
    pre_case = H.reset,
    post_case = function()
      vim.ui.select, vim.ui.open, vim.notify = original_select, original_open, original_notify
      vim.ui.input = original_input
      H.reset()
    end,
  },
})

-- Each test installs its UI adapter here; post_case restores the real functions.
---@param callback fun<T>(items: T[], opts: vim.ui.select.Opts, on_choice: fun(item: T?, idx?: integer))
local function set_select(callback)
  vim.ui.select = callback
end

---@param callback fun(opts: vim.ui.input.Opts?, on_confirm: fun(input?: string))
local function set_input(callback)
  vim.ui.input = callback
end

---@param callback fun(message: string, level?: integer)
local function set_notify(callback)
  vim.notify = callback
end

---@param callback fun(url: string)
local function set_open(callback)
  vim.ui.open = callback
end

---@param spec { items: agents.PickerItem<agents.Tool>[] }
---@param name string
---@return agents.PickerItem<agents.Tool>?
local function find_tool(spec, name)
  for _, item in ipairs(spec.items) do
    if item.data.name == name then
      return item
    end
  end
end

T["default adapter formats items and runs only the default action"] = function()
  ---@type agents.PickerItem<integer>?
  local selected
  local item = { text = "First item", data = 1 }
  ---@param items agents.PickerItem<integer>[]
  ---@param opts vim.ui.select.Opts
  ---@param callback fun(item: agents.PickerItem<integer>?, idx?: integer)
  set_select(function(items, opts, callback)
    test.expect.equality(items, { item })
    test.expect.equality(opts.prompt, "Test picker")
    test.expect.equality(assert(opts.format_item)(item), item.text)
    callback(item)
  end)
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
  set_select(function(_, _, callback)
    callback(nil)
  end)
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
  ---@type agents.PickerSpec<integer>?
  local received
  require("agents").setup({
    ---@param spec agents.PickerSpec<integer>
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

T["Snacks is loaded on demand and reports a missing dependency"] = function()
  ---@type table?
  local loaded = rawget(package.loaded, "snacks")
  ---@type (fun(name: string): unknown)?
  local preload = rawget(package.preload, "snacks")
  test.finally(function()
    rawset(package.loaded, "snacks", loaded)
    rawset(package.preload, "snacks", preload)
  end)
  local attempted = false
  rawset(package.loaded, "snacks", nil)
  rawset(package.preload, "snacks", function()
    attempted = true
    error("Snacks is unavailable for this test")
  end)
  require("agents").setup({ picker = "snacks" })
  test.expect.equality(attempted, false)
  set_select(function()
    error("The configured picker must not silently fall back")
  end)
  ---@type string?
  local notification
  set_notify(function(message, level)
    notification = message
    test.expect.equality(level, vim.log.levels.ERROR)
  end)
  picker.open({
    title = "Test picker",
    items = { { text = "Item", data = 1 } },
    default = "choose",
    actions = {
      choose = function()
        error("Missing picker must not choose an item")
      end,
    },
  })
  test.expect.equality(attempted, true)
  test.expect.equality(assert(notification):find("requires snacks.nvim", 1, true) ~= nil, true)
end

T["actions lists the top-level commands without including itself"] = function()
  ---@type agents.PickerSpec<agents.CommandName>?
  local received
  require("agents.config").get().picker = function(spec)
    received = spec
  end

  require("agents").actions()

  assert(received)
  test.expect.equality(received.title, "Agents: actions")
  test.expect.equality(received.default, "run")
  ---@type string[]
  local names = {}
  for _, item in ipairs(received.items) do
    names[#names + 1] = item.data
    test.expect.equality(item.text, item.data)
  end
  test.expect.equality(names, { "close", "focus", "hide", "new", "pick", "send", "toggle" })
  test.expect.equality(require("agents").sessions(), {})
end

T["actions restores the invoking window before dispatching toggle"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  ---@type agents.PickerSpec<agents.CommandName>?
  local received
  require("agents.config").get().picker = function(spec)
    received = spec
  end
  require("agents").actions()
  assert(received)
  vim.cmd.new()

  for _, item in ipairs(received.items) do
    if item.data == "toggle" then
      received.actions.run(item)
    end
  end

  test.expect.equality(vim.api.nvim_get_current_win(), origin)
  test.expect.equality(vim.fn.win_findbuf(session.buf), {})
  test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["actions refuses to dispatch after its invoking window closes"] = function()
  local session = H.new()
  local origin = vim.api.nvim_get_current_win()
  ---@type agents.PickerSpec<agents.CommandName>?
  local received
  require("agents.config").get().picker = function(spec)
    received = spec
  end
  ---@type string?
  local notification
  set_notify(function(message)
    notification = message
  end)
  require("agents").actions()
  assert(received)
  vim.api.nvim_win_close(origin, true)

  for _, item in ipairs(received.items) do
    if item.data == "close" then
      received.actions.run(item)
    end
  end

  test.expect.equality(require("agents").sessions(), { session })
  test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  test.expect.equality(
    notification,
    "agents.nvim: the window that opened the actions picker no longer exists"
  )
end

T["tools use the default adapter and launch the selected tool"] = function()
  ---@param items agents.PickerItem<agents.Tool>[]
  ---@param callback fun(item: agents.PickerItem<agents.Tool>?, idx?: integer)
  set_select(function(items, _, callback)
    callback(find_tool({ items = items }, "cat"))
  end)
  ---@type agents.Session?
  local session
  picker.tools(function(tool)
    session = require("agents").new(tool.name)
  end)
  assert(session)
  test.expect.equality(session.tool.name, "cat")
  test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
end

T["missing tools are annotated and selection reports the install URL"] = function()
  ---@type agents.PickerSpec<agents.Tool>?
  local received
  require("agents").setup({
    tools = {
      missing = { cmd = { "/__agents_missing_executable__" }, url = "https://example.com/install" },
      ignored = { cmd = { "cat" }, enabled = false },
    },
    ---@param spec agents.PickerSpec<agents.Tool>
    picker = function(spec)
      received = spec
    end,
  })
  ---@type { [1]: string, [2]: integer? }?
  local notification
  ---@type string?
  local opened
  set_notify(function(message, level)
    notification = { message, level }
  end)
  set_open(function(url)
    opened = url
  end)
  picker.tools(function()
    error("missing tool must not launch")
  end)

  assert(received)
  test.expect.equality(received.default, "new")
  test.expect.equality(type(received.actions.new), "function")
  test.expect.equality(find_tool(received, "ignored"), nil)
  local missing = assert(find_tool(received, "missing"))
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
  ---@type fun(item: agents.PickerItem<agents.Tool>?)?
  local callback
  ---@type agents.PickerItem<agents.Tool>[]?
  local items
  local origin = vim.api.nvim_get_current_win()
  ---@param values agents.PickerItem<agents.Tool>[]
  ---@param on_choice fun(item: agents.PickerItem<agents.Tool>?, idx?: integer)
  set_select(function(values, _, on_choice)
    items, callback = values, on_choice
  end)
  ---@type agents.Session?
  local session
  picker.tools(function(tool)
    session = require("agents").new(tool.name, { layout = "current" })
  end)
  vim.cmd("new")
  assert(callback)(find_tool({ items = assert(items) }, "cat"))
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
  assert(session)
  test.expect.equality(vim.api.nvim_win_get_buf(origin), session.buf)
end

T["tool selection reports a closed invoking window without launching"] = function()
  ---@type fun(item: agents.PickerItem<agents.Tool>?)?
  local callback
  ---@type agents.PickerItem<agents.Tool>[]?
  local items
  ---@type string?
  local notified
  local origin = vim.api.nvim_get_current_win()
  ---@param values agents.PickerItem<agents.Tool>[]
  ---@param on_choice fun(item: agents.PickerItem<agents.Tool>?, idx?: integer)
  set_select(function(values, _, on_choice)
    items, callback = values, on_choice
  end)
  set_notify(function(message)
    notified = message
  end)
  picker.tools(function()
    error("unexpected launch")
  end)
  vim.cmd("new")
  vim.api.nvim_win_close(origin, true)
  assert(callback)(find_tool({ items = assert(items) }, "cat"))
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
  local exited = assert(require("agents").new("sh", { args = { "exit 7" } }))
  test.expect.equality(
    vim.wait(1000, function()
      return exited.state == "exited"
    end),
    true
  )

  ---@type agents.Session?
  local selected
  ---@param items agents.PickerItem<agents.Session>[]
  ---@param opts vim.ui.select.Opts
  ---@param callback fun(item: agents.PickerItem<agents.Session>?, idx?: integer)
  set_select(function(items, opts, callback)
    test.expect.equality(
      vim.tbl_map(
        ---@param item agents.PickerItem<agents.Session>
        ---@return integer
        function(item)
          return item.data.id
        end,
        items
      ),
      { visible.id, exited.id, hidden.id, elsewhere.id }
    )
    test.expect.equality(items[1].text, visible.label .. "  [visible]  " .. visible.cwd)
    test.expect.equality(
      items[2].text,
      exited.label .. "  [exited]  " .. exited.cwd .. "  sh -c exit 7"
    )
    test.expect.equality(items[3].text, hidden.label .. "  [hidden]  " .. hidden.cwd)
    test.expect.equality(items[4].text, elsewhere.label .. "  [hidden]  " .. elsewhere.cwd)
    test.expect.equality(assert(opts.format_item)(items[1]), items[1].text)
    test.expect.equality(assert(opts.format_item)(items[4]), items[4].text)
    callback(items[3])
  end)
  picker.sessions(require("agents").sessions(), function(session)
    selected = session
  end)
  test.expect.equality(selected, hidden)
end

T["session picker ignores a session closed while it was open"] = function()
  local session = H.new()
  ---@type fun(item: agents.PickerItem<agents.Session>?)?
  local callback
  ---@type agents.PickerItem<agents.Session>?
  local item
  ---@param items agents.PickerItem<agents.Session>[]
  ---@param on_choice fun(item: agents.PickerItem<agents.Session>?, idx?: integer)
  set_select(function(items, _, on_choice)
    item, callback = items[1], on_choice
  end)
  picker.sessions({ session }, function()
    error("closed session must not be selected")
  end)
  require("agents").close(session.id)
  assert(callback)(item)
end

T["session selection reports a closed invoking window without showing"] = function()
  local session = H.new()
  require("agents").hide(session.id)
  local origin = vim.api.nvim_get_current_win()
  ---@type fun(item: agents.PickerItem<agents.Session>?)?
  local callback
  ---@type agents.PickerItem<agents.Session>?
  local item
  ---@type string?
  local notified
  ---@param items agents.PickerItem<agents.Session>[]
  ---@param on_choice fun(item: agents.PickerItem<agents.Session>?, idx?: integer)
  set_select(function(items, _, on_choice)
    item, callback = items[1], on_choice
  end)
  set_notify(function(message)
    notified = message
  end)
  picker.sessions({ session }, function(selected)
    require("agents").show(selected.id, { layout = "current" })
  end)
  vim.cmd("new")
  local unrelated = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_close(origin, true)
  assert(callback)(item)
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
  ---@type agents.PickerSpec<agents.Session>?
  local spec
  ---@param value agents.PickerSpec<agents.Session>
  require("agents.config").get().picker = function(value)
    spec = value
  end
  require("agents").pick()
  test.expect.equality(
    { assert(spec).items[1].data.id, assert(spec).items[2].data.id },
    { hidden.id, elsewhere.id }
  )
  test.expect.equality(assert(spec).items[1].text, hidden.label .. "  [hidden]  " .. hidden.cwd)
  test.expect.equality(
    assert(spec).items[2].text,
    elsewhere.label .. "  [hidden]  " .. elsewhere.cwd
  )
end

---@return fun(): agents.PickerSpec<agents.Tool>
local function capture_tools()
  ---@type agents.PickerSpec<agents.Tool>?
  local captured
  ---@param spec agents.PickerSpec<agents.Tool>
  require("agents.config").get().picker = function(spec)
    captured = spec
  end
  return function()
    return assert(captured)
  end
end

---@return fun(): agents.PickerSpec<agents.Session>
local function capture_sessions()
  ---@type agents.PickerSpec<agents.Session>?
  local captured
  ---@param spec agents.PickerSpec<agents.Session>
  require("agents.config").get().picker = function(spec)
    captured = spec
  end
  return function()
    return assert(captured)
  end
end

T["session rows follow native tab switches and multiple views"] = function()
  local session = H.new()
  local first_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  local second_tab = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_win_set_buf(0, session.buf)
  local get_spec = capture_sessions()

  ---@param state string
  local function expect_state(state)
    require("agents").pick()
    local item = get_spec().items[1]
    test.expect.equality(item.data.id, session.id)
    test.expect.equality(item.text, session.label .. "  [" .. state .. "]  " .. session.cwd)
  end

  expect_state("visible")
  vim.cmd.tabnew()
  expect_state("hidden")
  vim.api.nvim_set_current_tabpage(first_tab)
  expect_state("visible")
  vim.cmd.enew()
  expect_state("hidden")
  vim.api.nvim_set_current_tabpage(second_tab)
  expect_state("visible")
end

T["session picker reads current titles without changing labels or selection identity"] = function()
  local session = H.new({ label = "review" })
  session.title = "Investigate flaky tests"
  ---@type agents.Session?
  local selected
  ---@param items agents.PickerItem<agents.Session>[]
  ---@param opts vim.ui.select.Opts
  ---@param callback fun(item: agents.PickerItem<agents.Session>?, idx?: integer)
  set_select(function(items, opts, callback)
    test.expect.equality(
      assert(opts.format_item)(items[1]),
      "review · Investigate flaky tests  [visible]  " .. session.cwd
    )
    callback(items[1])
  end)
  picker.sessions({ session }, function(value)
    selected = value
  end)
  test.expect.equality(selected, session)

  local get_spec = capture_sessions()
  session.title = "Renamed conversation"
  require("agents").pick()
  local spec = get_spec()
  test.expect.equality(
    spec.items[1].text,
    "review · Renamed conversation  [visible]  " .. session.cwd
  )
  test.expect.equality(spec.items[1].data.id, session.id)
  test.expect.equality(spec.items[1].data.label, "review")
  session.title = nil
  require("agents").pick()
  test.expect.equality(get_spec().items[1].text, "review  [visible]  " .. session.cwd)
  require("agents").hide("review")
  test.expect.equality(vim.fn.win_findbuf(session.buf), {})
end

local layouts = { { "vsplit" }, { "split" }, { "tabnew" }, { "current" } }

---@param layout string
---@param origin integer
---@param tab integer
---@param buf integer
local function expect_layout(layout, origin, tab, buf)
  test.expect.equality(vim.api.nvim_get_current_buf(), buf)
  test.expect.equality(vim.api.nvim_get_current_win() == origin, layout == "current")
  test.expect.equality(vim.api.nvim_get_current_tabpage() == tab, layout ~= "tabnew")
  if layout == "vsplit" or layout == "split" then
    test.expect.equality(vim.fn.winlayout()[1], layout == "vsplit" and "row" or "col")
  end
end

T["tool layout actions"] = test.new_set({ parametrize = layouts }, {
  ---@param layout string
  ["launch from the invoking window and preserve launch options"] = function(layout)
    local get_spec = capture_tools()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    local opts = { args = { "-u" }, layout = "float", label = "custom" }
    require("agents").new(nil, opts)
    local spec = get_spec()
    vim.cmd.tabnew()
    spec.actions[layout](assert(find_tool(spec, "cat")))
    local session = assert(require("agents").current())
    expect_layout(layout, origin, tab, session.buf)
    test.expect.equality(session.cmd, { "cat", "-u" })
    test.expect.equality(session.label, "custom")
    test.expect.equality(opts, { args = { "-u" }, layout = "float", label = "custom" })
  end,
})

T["edit arguments runs the full argv and retains the original tool"] = function()
  local get_spec = capture_tools()
  local origin = vim.api.nvim_get_current_win()
  ---@type vim.ui.input.Opts?
  local input_opts
  ---@type fun(input?: string)?
  local input_callback
  set_input(function(opts, callback)
    input_opts, input_callback = opts, callback
  end)
  require("agents").new(nil, { args = { "-u" }, layout = "current" })
  local spec = get_spec()
  spec.actions.edit_args(assert(find_tool(spec, "cat")))
  test.expect.equality(assert(input_opts).default, "cat -u")
  vim.cmd.tabnew()
  assert(input_callback)("  printf \t %s\\n edited-argv  ")
  local session = assert(require("agents").current())
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
  test.expect.equality(session.cmd, { "printf", "%s\\n", "edited-argv" })
  test.expect.equality(session.tool.cmd, { "cat" })
  test.expect.equality(session.tool.name, "cat")
  test.expect.equality(session.label, "cat")
  H.wait(function()
    return session.state == "exited"
  end)
  local output = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
  test.expect.equality(output:find("edited%-argv") ~= nil, true)
  local get_sessions = capture_sessions()
  require("agents").pick()
  test.expect.equality(get_sessions().items[1].text:find("printf %%s\\n edited%-argv") ~= nil, true)
end

T["edit arguments treats shell syntax as literal argv"] = function()
  local get_spec = capture_tools()
  set_input(function(_, callback)
    callback([[printf %s 'quoted word' $HOME ; echo unsafe]])
  end)
  require("agents").new()
  local spec = get_spec()
  spec.actions.edit_args(assert(find_tool(spec, "cat")))
  local session = assert(require("agents").current())
  test.expect.equality(
    session.cmd,
    { "printf", "%s", "'quoted", "word'", "$HOME", ";", "echo", "unsafe" }
  )
end

T["edit arguments cancellation and empty input do not launch"] = function()
  local get_spec = capture_tools()
  ---@type string?
  local message
  set_notify(function(value)
    message = value
  end)
  for _, value in ipairs({ false, " \t " }) do
    set_input(function(_, callback)
      callback(value or nil)
    end)
    require("agents").new()
    local spec = get_spec()
    spec.actions.edit_args(assert(find_tool(spec, "cat")))
    test.expect.equality(#require("agents").sessions(), 0)
  end
  test.expect.equality(message, "agents.nvim: command must not be empty")
end

T["edit arguments stops when the invoking window closes during input"] = function()
  local get_spec = capture_tools()
  local origin = vim.api.nvim_get_current_win()
  ---@type fun(input?: string)?
  local callback
  ---@type string?
  local message
  set_input(function(_, on_input)
    callback = on_input
  end)
  set_notify(function(value)
    message = value
  end)
  require("agents").new()
  local spec = get_spec()
  spec.actions.edit_args(assert(find_tool(spec, "cat")))
  vim.cmd.new()
  vim.api.nvim_win_close(origin, true)
  assert(callback)("cat")
  test.expect.equality(#require("agents").sessions(), 0)
  test.expect.equality(
    message,
    "agents.nvim: the window that opened the tool picker no longer exists"
  )
end

T["session layout actions"] = test.new_set({ parametrize = layouts }, {
  ---@param layout string
  ["show hidden sessions from the invoking window"] = function(layout)
    local get_spec = capture_sessions()
    local session = H.new()
    require("agents").hide(session.id)
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("agents").pick()
    local spec = get_spec()
    vim.cmd.tabnew()
    spec.actions[layout](spec.items[1])
    expect_layout(layout, origin, tab, session.buf)
    test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
  ---@param layout string
  ["reuse a visible session instead of opening another view"] = function(layout)
    local get_spec = capture_sessions()
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.tabnew()
    require("agents").pick()
    local spec = get_spec()
    spec.actions[layout](spec.items[1])
    test.expect.equality(vim.api.nvim_get_current_win(), win)
    test.expect.equality(vim.fn.win_findbuf(session.buf), { win })
  end,
})

T["session hide and close actions preserve or terminate the job"] = function()
  local get_spec = capture_sessions()
  local session = H.new()
  require("agents").pick()
  local spec = get_spec()
  spec.actions.hide(spec.items[1])
  test.expect.equality(vim.fn.win_findbuf(session.buf), {})
  test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  require("agents").pick()
  spec = get_spec()
  spec.actions.close(spec.items[1])
  test.expect.equality(require("agents.session").get(session.id), nil)
  H.wait(function()
    return not vim.api.nvim_buf_is_valid(session.buf)
      and vim.fn.jobwait({ session.job }, 0)[1] ~= -1
  end)
end

T["all session actions ignore stale selections"] = function()
  local get_spec = capture_sessions()
  local session = H.new()
  require("agents").pick()
  local spec = get_spec()
  require("agents").close(session.id)
  for _, action in pairs(spec.actions) do
    action(spec.items[1])
  end
  test.expect.equality(#require("agents").sessions(), 0)
end

return T
