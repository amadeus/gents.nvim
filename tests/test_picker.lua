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
  test.expect.equality(received.title, "Agents: Actions")
  test.expect.equality(received.default, "run")
  ---@type table<agents.CommandName, string>
  local descriptions = {
    close = "Hide and kill a session",
    focus = "Switch focus between an agent and your last buffer",
    hide = "Hide a session without killing it",
    new = "Start a new session",
    pick = "Existing session picker",
    send = "Pick context to send to an agent",
    toggle = "Show or hide a session",
  }
  ---@type string[]
  local names = {}
  for _, item in ipairs(received.items) do
    names[#names + 1] = item.data
    ---@type string
    local name = item.data .. string.rep(" ", 6 - #item.data)
    test.expect.equality(item.text, name .. " · " .. descriptions[item.data])
    test.expect.equality(item.chunks, {
      { text = name },
      { text = " · ", kind = "separator" },
      { text = descriptions[item.data], kind = "description" },
    })
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

T["context rows distinguish prompts from providers and align only available entries"] = function()
  local origin = vim.api.nvim_get_current_win()
  local prompt = { { text = "Saved buffer prompt" } }
  require("agents.config").get().prompts = {
    buffer = prompt,
    ["説明説明説明"] = { { text = "Explain this" } },
    unavailable_prompt_with_a_very_long_name = { "selection" },
  }
  ---@type agents.PickerSpec<agents.Part[]>?
  local received
  require("agents.config").get().picker = function(spec)
    received = spec
  end
  ---@type agents.Part[]?
  local chosen
  picker.context(require("agents.context").capture(), function(parts)
    chosen = parts
  end)
  assert(received)
  test.expect.equality(received.items[1].text, "buffer       · Saved prompt")
  test.expect.equality(received.items[2].text, "説明説明説明 · Saved prompt")
  test.expect.equality(received.items[1].preview, "Saved buffer prompt")
  test.expect.equality(received.items[1].data, prompt)
  ---@type agents.PickerItem<agents.Part[]>?
  local buffer
  for _, item in ipairs(received.items) do
    local chunks = assert(item.chunks)
    test.expect.equality(vim.fn.strdisplaywidth(chunks[1].text), 12)
    test.expect.equality(chunks[2], { text = " · ", kind = "separator" })
    test.expect.equality(chunks[3].kind, "description")
    test.expect.equality(item.text, chunks[1].text .. chunks[2].text .. chunks[3].text)
    if chunks[3].text == "Copy entire buffer text" then
      buffer = item
    end
  end
  assert(buffer)
  test.expect.equality(buffer.text, "buffer       · Copy entire buffer text")
  test.expect.equality(buffer.data, { { code = "", ft = "" } })
  vim.cmd.new()
  received.actions.send(received.items[1])
  test.expect.equality(chosen, prompt)
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
  received.actions.send(buffer)
  test.expect.equality(chosen, buffer.data)
end

T["context orders common providers and inserts selection after line when available"] = function()
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/picker-context.lua")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local example = true" })
  vim.api.nvim_echo({ { "Picker context message" } }, true, {})
  test.finally(function()
    vim.cmd("messages clear")
  end)
  require("agents.config").get().prompts = { example = { { text = "Saved prompt" } } }
  ---@type agents.PickerSpec<agents.Part[]>?
  local received
  require("agents.config").get().picker = function(spec)
    received = spec
  end

  for _, selected in ipairs({ false, true }) do
    local ctx = require("agents.context").capture(selected and { line1 = 1, line2 = 1 } or nil)
    picker.context(ctx, function() end)
    assert(received)
    ---@type string[]
    local names = {}
    for _, item in ipairs(received.items) do
      names[#names + 1] = vim.trim(assert(item.chunks)[1].text)
    end
    local expected = selected and { "example", "line", "selection", "file", "buffer", "messages" }
      or { "example", "line", "file", "buffer", "messages" }
    test.expect.equality(vim.list_slice(names, 1, #expected), expected)
    test.expect.equality(vim.tbl_contains(names, "selection"), selected)
    test.expect.equality(vim.tbl_contains(names, "position"), false)
  end
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
      cat = { cmd = { "cat" } },
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
  local installed = assert(find_tool(received, "cat"))
  test.expect.equality(installed.text, "cat")
  test.expect.equality(installed.chunks, nil)
  local missing = assert(find_tool(received, "missing"))
  local width = 0
  for _, item in ipairs(received.items) do
    width = math.max(width, vim.fn.strdisplaywidth(item.data.name))
  end
  local name = "missing" .. string.rep(" ", width - 7)
  test.expect.equality(missing.hl, "Comment")
  test.expect.equality(missing.text, name .. " · Not installed")
  test.expect.equality(missing.chunks, {
    { text = name },
    { text = " · ", kind = "separator" },
    { text = "Not installed", kind = "description" },
  })
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
    local directory = vim.fn.fnamemodify(visible.cwd, ":~")
    test.expect.equality(
      items[1].text,
      "●  cat #3 · Untitled" .. string.rep(" ", 10) .. " · " .. directory
    )
    test.expect.equality(
      items[2].text,
      "●  sh     · Untitled  [exited] · " .. directory .. "  sh -c exit 7"
    )
    test.expect.equality(
      items[3].text,
      "○  cat #2 · Untitled" .. string.rep(" ", 10) .. " · " .. directory
    )
    test.expect.equality(
      items[4].text,
      "○  cat    · Untitled" .. string.rep(" ", 10) .. " · " .. directory
    )
    test.expect.equality(assert(items[1].chunks)[1], { text = "●", kind = "visible" })
    test.expect.equality(assert(items[2].chunks)[1], { text = "●", kind = "visible" })
    test.expect.equality(assert(items[3].chunks)[1], { text = "○", kind = "hidden" })
    test.expect.equality(assert(opts.format_item)(items[1]), items[1].text)
    test.expect.equality(assert(opts.format_item)(items[4]), items[4].text)
    callback(items[3])
  end)
  picker.sessions(require("agents").sessions(), function(session)
    selected = session
  end)
  test.expect.equality(selected, hidden)

  require("agents").hide(exited.id)
  ---@param items agents.PickerItem<agents.Session>[]
  set_select(function(items)
    test.expect.equality(
      items[1].text,
      "○  sh · Untitled  [exited] · "
        .. vim.fn.fnamemodify(exited.cwd, ":~")
        .. "  sh -c exit 7"
    )
    test.expect.equality(assert(items[1].chunks)[1], { text = "○", kind = "hidden" })
  end)
  picker.sessions({ exited }, function() end)
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
  test.expect.equality(
    assert(spec).items[1].text,
    "○  cat #2 · Untitled · " .. vim.fn.fnamemodify(hidden.cwd, ":~")
  )
  test.expect.equality(
    assert(spec).items[2].text,
    "○  cat    · Untitled · " .. vim.fn.fnamemodify(elsewhere.cwd, ":~")
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

T["custom session markers follow native tab switches and multiple views"] = function()
  local session = H.new()
  require("agents").setup({ icons = { visible = "v", hidden = "h" } })
  local first_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  local second_tab = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_win_set_buf(0, session.buf)
  local get_spec = capture_sessions()

  ---@param marker string
  local function expect_marker(marker)
    require("agents").pick()
    local item = get_spec().items[1]
    test.expect.equality(item.data.id, session.id)
    test.expect.equality(
      item.text,
      marker .. "  " .. session.label .. " · Untitled · " .. vim.fn.fnamemodify(session.cwd, ":~")
    )
    test.expect.equality(
      assert(item.chunks)[1],
      { text = marker, kind = marker == "v" and "visible" or "hidden" }
    )
  end

  expect_marker("v")
  vim.cmd.tabnew()
  expect_marker("h")
  vim.api.nvim_set_current_tabpage(first_tab)
  expect_marker("v")
  vim.cmd.enew()
  expect_marker("h")
  vim.api.nvim_set_current_tabpage(second_tab)
  expect_marker("v")
end

T["session columns align display cells across titles labels and visibility"] = function()
  require("agents").setup({
    icons = { visible = "界", hidden = "." },
    tools = { cat = { cmd = { "cat" } }, assistant = { cmd = { "cat" } } },
  })
  local titled = H.new()
  titled.title = "日本語 é"
  local numbered = H.new()
  local assistant = assert(require("agents").new("assistant"))
  assistant.title = "Plan"
  local custom = H.new({ label = "review-long" })
  require("agents").hide(numbered.id)
  require("agents").hide(custom.id)
  test.expect.equality(numbered.label, "cat #2")

  ---@type { session: agents.Session, name: string, title?: string, marker: string }[]
  local rows = {
    { session = titled, name = "cat", title = "日本語 é", marker = "界" },
    { session = assistant, name = "assistant", title = "Plan", marker = "界" },
    { session = numbered, name = "cat #2", marker = "." },
    { session = custom, name = "review-long", marker = "." },
  }
  ---@param text string
  ---@param value string
  ---@return integer
  local function column(text, value)
    local start = assert(text:find(value, 1, true))
    return vim.fn.strdisplaywidth(text:sub(1, start - 1))
  end

  ---@type agents.Session?
  local selected
  local get_spec = capture_sessions()
  picker.sessions({ custom, assistant, numbered, titled }, function(session)
    selected = session
  end)
  local spec = get_spec()
  test.expect.equality(#spec.items, #rows)
  for index, row in ipairs(rows) do
    local item = spec.items[index]
    local directory = vim.fn.fnamemodify(row.session.cwd, ":~")
    test.expect.equality(rawequal(item.data, row.session), true)
    -- All offsets are terminal cells, including wide glyphs and combining accents.
    test.expect.equality(column(item.text, row.name), 4)
    test.expect.equality(column(item.text, directory), 29)
    test.expect.equality(column(item.text, "·"), 16)
    test.expect.equality(column(item.text, "· " .. directory), 27)
    test.expect.equality(column(item.text, row.title or "Untitled"), 18)
    local chunks = assert(item.chunks)
    test.expect.equality(chunks[1], {
      text = row.marker,
      kind = row.marker == "界" and "visible" or "hidden",
    })
    ---@type string[]
    local parts = {}
    local directories, placeholders, separators = 0, 0, 0
    for _, chunk in ipairs(chunks) do
      parts[#parts + 1] = chunk.text
      if chunk.kind == "directory" then
        directories = directories + 1
        test.expect.equality(chunk.text, directory)
      elseif chunk.kind == "placeholder" then
        placeholders = placeholders + 1
        test.expect.equality(chunk.text, "Untitled")
      elseif chunk.kind == "separator" then
        separators = separators + 1
        test.expect.equality(chunk.text, " · ")
      end
    end
    test.expect.equality(table.concat(parts), item.text)
    test.expect.equality(directories, 1)
    test.expect.equality(separators, 2)
    test.expect.equality(placeholders, row.title and 0 or 1)
    spec.actions.show(item)
    test.expect.equality(rawequal(selected, row.session), true)
  end
end

T["session title display caps width without changing stored titles"] = function()
  local session = H.new()
  local get_spec = capture_sessions()
  ---@type { full: string, shown: string }[]
  local titles = {
    { full = string.rep("a", 60), shown = string.rep("a", 60) },
    { full = string.rep("a", 61), shown = string.rep("a", 57) .. "..." },
    { full = string.rep("界", 30), shown = string.rep("界", 30) },
    { full = string.rep("界", 31), shown = string.rep("界", 28) .. "..." },
    { full = string.rep("é", 61), shown = string.rep("é", 57) .. "..." },
    { full = string.rep("界é", 22), shown = string.rep("界é", 19) .. "..." },
  }
  for _, title in ipairs(titles) do
    session.title = title.full
    picker.sessions({ session }, function() end)
    local item = get_spec().items[1]
    test.expect.equality(
      item.text,
      "●  cat · " .. title.shown .. " · " .. vim.fn.fnamemodify(session.cwd, ":~")
    )
    test.expect.equality(assert(item.chunks)[4], { text = title.shown })
    test.expect.equality(vim.fn.strdisplaywidth(title.shown) <= 60, true)
    test.expect.equality(rawequal(item.data, session), true)
    test.expect.equality(session.title, title.full)
  end
end

T["session directories abbreviate the home component only for display"] = function()
  local session = H.new()
  local home = vim.fn.expand("~")
  local get_spec = capture_sessions()
  ---@type { cwd: string, shown: string }[]
  local paths = {
    { cwd = home, shown = "~" },
    { cwd = home .. "/projects", shown = "~/projects" },
    { cwd = home .. "-other/project", shown = home .. "-other/project" },
  }
  for _, path in ipairs(paths) do
    session.cwd = path.cwd
    picker.sessions({ session }, function() end)
    local item = get_spec().items[1]
    test.expect.equality(item.text, "●  cat · Untitled · " .. path.shown)
    local directories = 0
    for _, chunk in ipairs(assert(item.chunks)) do
      if chunk.kind == "directory" then
        directories = directories + 1
        test.expect.equality(chunk.text, path.shown)
      end
    end
    test.expect.equality(directories, 1)
    test.expect.equality(rawequal(item.data, session), true)
    test.expect.equality(session.cwd, path.cwd)
  end
end

T["session chunks preserve full text and mark visibility and directory"] = function()
  local session = H.new({
    label = "review [●] λ",
    cmd = { "sh", "-c", "exec cat", "argument [○] %λ" },
  })
  session.title = "Check [hidden] · 日本語"
  session.cwd = "/project [○]/日本語 folder"
  local get_spec = capture_sessions()
  require("agents").pick()
  local item = get_spec().items[1]
  test.expect.equality(item.data, session)
  test.expect.equality(
    item.text,
    "●  cat · Check [hidden] · 日本語 · /project [○]/日本語 folder  sh -c exec cat argument [○] %λ"
  )
  ---@type string[]
  local parts = {}
  local directories = 0
  for i, chunk in ipairs(assert(item.chunks)) do
    parts[#parts + 1] = chunk.text
    if i == 1 then
      test.expect.equality(chunk, { text = "●", kind = "visible" })
    elseif chunk.kind == "directory" then
      directories = directories + 1
      test.expect.equality(chunk.text, session.cwd)
    elseif chunk.kind == "separator" then
      test.expect.equality(chunk.text, " · ")
    else
      test.expect.equality(chunk.kind, nil)
    end
  end
  test.expect.equality(table.concat(parts), item.text)
  test.expect.equality(directories, 1)
end

T["session picker reads current titles without changing labels or selection identity"] = function()
  H.new()
  local session = H.new()
  test.expect.equality(session.label, "cat #2")
  session.title = "Investigate flaky tests"
  ---@type agents.Session?
  local selected
  ---@param items agents.PickerItem<agents.Session>[]
  ---@param opts vim.ui.select.Opts
  ---@param callback fun(item: agents.PickerItem<agents.Session>?, idx?: integer)
  set_select(function(items, opts, callback)
    test.expect.equality(
      assert(opts.format_item)(items[1]),
      "●  cat · Investigate flaky tests · " .. vim.fn.fnamemodify(session.cwd, ":~")
    )
    callback(items[1])
  end)
  picker.sessions({ session }, function(value)
    selected = value
  end)
  test.expect.equality(selected, session)

  local get_spec = capture_sessions()
  session.title = "Renamed conversation"
  picker.sessions({ session }, function() end)
  local spec = get_spec()
  test.expect.equality(
    spec.items[1].text,
    "●  cat · Renamed conversation · " .. vim.fn.fnamemodify(session.cwd, ":~")
  )
  test.expect.equality(spec.items[1].data.id, session.id)
  test.expect.equality(spec.items[1].data.label, "cat #2")
  session.title = nil
  picker.sessions({ session }, function() end)
  test.expect.equality(
    get_spec().items[1].text,
    "●  cat #2 · Untitled · " .. vim.fn.fnamemodify(session.cwd, ":~")
  )
  require("agents").hide("cat #2")
  test.expect.equality(vim.fn.win_findbuf(session.buf), {})
end

local layouts = { { "vsplit" }, { "split" }, { "tabnew" }, { "float" }, { "current" } }

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
  elseif layout == "float" then
    test.expect.equality(vim.api.nvim_win_get_config(0).relative, "editor")
  end
end

T["tool layout actions"] = test.new_set({ parametrize = layouts }, {
  ---@param layout string
  ["launch from the invoking window and preserve launch options"] = function(layout)
    local get_spec = capture_tools()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    local requested = layout == "float" and "current" or "float"
    local opts = { args = { "-u" }, layout = requested, label = "custom" }
    require("agents").new(nil, opts)
    local spec = get_spec()
    vim.cmd.tabnew()
    spec.actions[layout](assert(find_tool(spec, "cat")))
    local session = assert(require("agents").current())
    expect_layout(layout, origin, tab, session.buf)
    test.expect.equality(session.cmd, { "cat", "-u" })
    test.expect.equality(session.label, "custom")
    test.expect.equality(opts, { args = { "-u" }, layout = requested, label = "custom" })
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
  ["honor explicit placement while preserving a session view in another tab"] = function(layout)
    local get_spec = capture_sessions()
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.tabnew()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("agents").pick()
    local spec = get_spec()
    vim.cmd.tabnew()
    spec.actions[layout](spec.items[1])
    expect_layout(layout, origin, tab, session.buf)
    test.expect.equality(vim.api.nvim_win_get_buf(win), session.buf)
    test.expect.equality(#vim.fn.win_findbuf(session.buf), 2)
    test.expect.equality(require("agents").sessions(), { session })
    test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
})

T["session current action"] = test.new_set({ parametrize = { { false }, { true } } }, {
  ---@param already_current boolean
  ["uses the invoking window even when the session is already visible in this tab"] = function(
    already_current
  )
    local get_spec = capture_sessions()
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    if not already_current then
      vim.cmd.new()
    end
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("agents").pick()
    local spec = get_spec()
    vim.cmd.tabnew()
    spec.actions.current(spec.items[1])
    expect_layout("current", origin, tab, session.buf)
    test.expect.equality(vim.api.nvim_win_get_buf(win), session.buf)
    test.expect.equality(#vim.fn.win_findbuf(session.buf), already_current and 1 or 2)
    test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
})

T["session hide and close actions preserve or terminate the job"] = function()
  local get_spec = capture_sessions()
  local session = H.new()
  local split = vim.api.nvim_get_current_win()
  vim.cmd.tabnew()
  require("agents").pick()
  local spec = get_spec()
  spec.actions.float(spec.items[1])
  local float = vim.api.nvim_get_current_win()
  test.expect.equality(#vim.fn.win_findbuf(session.buf), 2)
  require("agents").pick()
  spec = get_spec()
  spec.actions.hide(spec.items[1])
  test.expect.equality(vim.fn.win_findbuf(session.buf), {})
  test.expect.equality(vim.api.nvim_win_is_valid(float), false)
  test.expect.equality(vim.api.nvim_win_is_valid(split), false)
  test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  test.expect.equality(require("agents.session").get(session.id), session)
  require("agents").pick()
  spec = get_spec()
  spec.actions.float(spec.items[1])
  float = vim.api.nvim_get_current_win()
  require("agents").pick()
  spec = get_spec()
  spec.actions.close(spec.items[1])
  test.expect.equality(vim.api.nvim_win_is_valid(float), false)
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
