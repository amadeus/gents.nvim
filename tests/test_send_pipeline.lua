local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality
local original_notify = vim.notify
local original_select = vim.ui.select
---@param callback fun(message: string, level?: integer, opts?: table)
local function set_notify(callback)
  vim.notify = callback
end
---@param callback fun<T>(items: T[], opts: vim.ui.select.Opts, on_choice: fun(item: T?, idx?: integer))
local function set_select(callback)
  vim.ui.select = callback
end
---@type gents.PickerSpec<unknown>[]
local pickers
---@type string[]
local notifications
---@type string
local temp_dir
local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      temp_dir = vim.fn.tempname()
      vim.fn.mkdir(temp_dir, "p")
      pickers, notifications = {}, {}
      set_notify(function(message)
        notifications[#notifications + 1] = message
      end)
      gents.setup({
        tools = { cat = { cmd = { "sh", "-c", "printf '1\\n2\\n3\\n4\\n5\\n6\\n'; exec cat" } } },
        prompts = {
          explain = { { text = "Explain:" }, { any = { "selection", "line" } } },
          selected = { "selection" },
        },
        ---@param spec gents.PickerSpec<unknown>
        picker = function(spec)
          pickers[#pickers + 1] = spec
        end,
      })
      vim.api.nvim_buf_set_name(0, vim.fs.joinpath(vim.fn.getcwd(), "context.lua"))
      vim.api.nvim_buf_set_lines(
        0,
        0,
        -1,
        false,
        { "local first = 1", "  local second = 2", "return first" }
      )
      vim.bo.filetype = "lua"
      vim.api.nvim_win_set_cursor(0, { 2, 4 })
    end,
    post_case = function()
      set_notify(original_notify)
      set_select(original_select)
      H.reset()
      vim.fn.delete(temp_dir, "d")
    end,
  },
})

---@param session gents.Session
---@return string
local function output(session)
  return table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
end

---@param spec gents.PickerSpec<unknown>
---@param name string
---@return gents.PickerItem<unknown>?
local function find(spec, name)
  for _, item in ipairs(spec.items) do
    if item.text:match("^%S+") == name then
      return item
    end
  end
end

---@param spec gents.PickerSpec<unknown>
---@param name string
local function choose(spec, name)
  spec.actions[spec.default](assert(find(spec, name)))
end

T["send to a hidden target"] = test.new_set({ parametrize = { { true }, { false } } }, {
  ---@param focus boolean
  ["honors focus without disturbing source cursor or later navigation"] = function(focus)
    local origin = vim.api.nvim_get_current_win()
    local session = H.new()
    gents.hide(session.id)
    vim.api.nvim_set_current_win(origin)
    local cursor = vim.api.nvim_win_get_cursor(origin)
    ---@type gents.SendOptions
    local opts = { target = session.id }
    if not focus then
      opts.focus = false
    end
    eq(gents.send({ "line" }, opts), session)
    eq(vim.api.nvim_get_current_buf() == session.buf, focus)
    eq(vim.api.nvim_get_current_win() == origin, not focus)
    eq(vim.api.nvim_win_get_cursor(origin), cursor)
    eq(require("gents.window").visible(session), true)
    -- Delivery is queued; returning to the editor must survive the actual paste.
    vim.api.nvim_set_current_win(origin)
    H.wait(function()
      return output(session):find("@context.lua:2", 1, true) ~= nil
    end)
    eq(vim.api.nvim_get_current_win(), origin)
    eq(vim.api.nvim_win_get_cursor(origin), cursor)
  end,
})

T["a target visible in another tab gets a view in the invoking tab"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_win(origin)
  local tab = vim.api.nvim_get_current_tabpage()
  gents.send({ "file" }, { target = session.id })
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_get_current_tabpage(), tab)
  eq(#vim.fn.win_findbuf(session.buf), 2)
  H.wait(function()
    return output(session):find("@context.lua", 1, true) ~= nil
  end)
end

T["focused target locations use the captured source cwd"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  session.tool.location = function(path, range)
    return "CUSTOM:" .. path .. ":" .. assert(range).start[1]
  end
  vim.cmd.lcd(temp_dir)
  vim.api.nvim_set_current_win(origin)
  gents.send({ "line" }, { target = session.id })
  eq(vim.api.nvim_get_current_buf(), session.buf)
  H.wait(function()
    return output(session):find("CUSTOM:context.lua:2", 1, true) ~= nil
  end)
end

T["context picker omits unavailable providers and prompts and previews defaults"] = function()
  gents.send()
  local spec = assert(pickers[1])
  eq(spec.title, "Gents: Send Context")
  eq(assert(find(spec, "file")).preview, "@context.lua")
  eq(find(spec, "selection"), nil)
  eq(find(spec, "selected"), nil)
  eq(assert(find(spec, "explain")).preview, "Explain:\n@context.lua:2")
end

T["session sources"] = test.new_set({ parametrize = { { false }, { true } } }, {
  ---@param only boolean
  ["reject picker and direct sends without changing focus"] = function(only)
    local session = H.new()
    if only then
      vim.cmd.only()
    end
    local origin = vim.api.nvim_get_current_win()
    local mode = vim.api.nvim_get_mode().mode
    local sends = {
      function()
        eq(gents.send(), nil)
      end,
      function()
        eq(gents.send({ "file" }), nil)
      end,
      function()
        eq(gents.send({ { text = "Literal prompt" } }), nil)
      end,
      function()
        vim.cmd("Gents send")
      end,
      function()
        vim.cmd("Gents send explain")
      end,
      function()
        vim.cmd("1Gents send")
      end,
      function()
        vim.cmd("Gents actions send")
      end,
      function()
        vim.cmd("1Gents actions send --no-focus --target " .. session.id)
      end,
    }
    for _, send in ipairs(sends) do
      notifications = {}
      send()
      eq(notifications, { "gents.nvim: send context from a non-session buffer" })
      eq(pickers, {})
      eq(vim.api.nvim_get_current_win(), origin)
      eq(vim.api.nvim_get_current_buf(), session.buf)
      eq(vim.api.nvim_get_mode().mode, mode)
      eq(gents.sessions(), { session })
    end
  end,
})

T["two asynchronous send pickers"] = test.new_set({ parametrize = { { true }, { false } } }, {
  ---@param focus boolean
  ["preserve the original parts and honor focus after selecting a target"] = function(focus)
    local origin = vim.api.nvim_get_current_win()
    local source = vim.api.nvim_get_current_buf()
    local first = H.new()
    gents.hide(first.id)
    local second = H.new()
    gents.hide(second.id)
    vim.api.nvim_set_current_win(origin)
    gents.send(nil, focus and {} or { focus = false })
    eq(vim.api.nvim_get_current_win(), origin)
    local context_picker = assert(pickers[1])
    local preview = assert(find(context_picker, "buffer")).preview
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "changed after capture" })
    vim.api.nvim_buf_set_name(source, vim.fs.joinpath(vim.fn.getcwd(), "changed.lua"))
    vim.cmd("new")
    choose(context_picker, "buffer")
    local target_picker = assert(pickers[2])
    eq(target_picker.title, "Gents: Sessions")
    eq(vim.api.nvim_get_current_win(), origin)
    eq(vim.fn.win_findbuf(second.buf), {})
    vim.cmd("new")
    eq(target_picker.items[2].data, second)
    target_picker.actions[target_picker.default](target_picker.items[2])
    eq(vim.api.nvim_get_current_buf() == second.buf, focus)
    eq(vim.api.nvim_get_current_win() == origin, not focus)
    H.wait(function()
      return output(second):find("local second = 2", 1, true) ~= nil
    end)
    eq(output(second):find("changed after capture", 1, true), nil)
    eq(output(first):find("local second = 2", 1, true), nil)
    eq(assert(find(context_picker, "buffer")).preview, preview)
  end,
})

T["target picker cannot change an already resolved provider or source path"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  gents.hide(session.id)
  gents.hide(H.new().id)
  vim.api.nvim_set_current_win(origin)
  gents.send({ "line" })
  local spec = assert(pickers[1])
  vim.api.nvim_buf_set_name(0, vim.fs.joinpath(vim.fn.getcwd(), "renamed.lua"))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.lcd(temp_dir)
  eq(spec.items[1].data, session)
  spec.actions[spec.default](spec.items[1])
  eq(vim.api.nvim_get_current_buf(), session.buf)
  H.wait(function()
    return output(session):find("@context.lua:2", 1, true) ~= nil
  end)
end

T["unknown and unavailable items send nothing and do not open target pickers"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  gents.hide(session.id)
  vim.api.nvim_set_current_win(origin)
  test.expect.error(function()
    gents.send({ "file", "missing-provider" })
  end, "unknown provider")
  eq(gents.send({ "file", "selection" }), nil)
  eq(#notifications, 1)
  eq(#pickers, 0)
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(vim.api.nvim_get_current_win(), origin)
end

T["ranged command sends selected lines directly and named prompts expand"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  vim.cmd("2Gents send")
  H.wait(function()
    return output(session):find("local second = 2", 1, true) ~= nil
  end)
  eq(output(session):find("local first = 1", 1, true), nil)
  eq(#pickers, 0)
  eq(vim.api.nvim_get_current_buf(), session.buf)
  vim.api.nvim_set_current_win(origin)
  vim.cmd("Gents send explain")
  H.wait(function()
    return output(session):find("Explain:", 1, true) ~= nil
  end)
end

T["context send without sessions"] = test.new_set({ parametrize = { { true }, { false } } }, {
  ---@param focus boolean
  ["launches the selected tool and preserves captured parts across both pickers"] = function(focus)
    local origin, source = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    require("gents.config").get().prompts.snapshot = { "file", "buffer" }
    gents.send(nil, focus and {} or { focus = false })
    local context_picker = assert(pickers[1])
    eq(context_picker.title, "Gents: Send Context")
    eq(gents.sessions(), {})
    local preview = assert(find(context_picker, "snapshot")).preview
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "changed after capture" })
    vim.api.nvim_buf_set_name(source, vim.fs.joinpath(vim.fn.getcwd(), "renamed.lua"))
    vim.cmd.new()
    choose(context_picker, "snapshot")
    local tool_picker = assert(pickers[2])
    eq(tool_picker.title, "Gents: New Session")
    eq(vim.api.nvim_get_current_win(), origin)
    eq(gents.sessions(), {})
    vim.cmd.new()
    choose(tool_picker, "cat")
    local session = assert(gents.sessions()[1])
    eq(#gents.sessions(), 1)
    eq(session.tool.name, "cat")
    eq(vim.api.nvim_get_current_buf() == session.buf, focus)
    eq(vim.api.nvim_get_current_win() == origin, not focus)
    eq(vim.api.nvim_win_get_buf(origin), source)
    H.wait(function()
      return output(session):find("local second = 2", 1, true) ~= nil
    end)
    eq(output(session):find("@context.lua", 1, true) ~= nil, true)
    eq(output(session):find("changed after capture", 1, true), nil)
    eq(output(session):find("renamed.lua", 1, true), nil)
    eq(assert(find(context_picker, "snapshot")).preview, preview)
    eq(#pickers, 2)
    eq(notifications, {})
  end,
})

T["direct send without sessions uses the selected tool formatter and captured location"] = function()
  local cwd = vim.fn.getcwd(0)
  require("gents.config").get().tools.cat.location = function(path, range)
    return "CUSTOM:" .. path .. ":" .. assert(range).start[1]
  end
  gents.send({ "line" })
  local spec = assert(pickers[1])
  eq(spec.title, "Gents: New Session")
  vim.api.nvim_buf_set_name(0, vim.fs.joinpath(vim.fn.getcwd(), "renamed.lua"))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.lcd(temp_dir)
  choose(spec, "cat")
  local session = assert(gents.sessions()[1])
  eq(session.cwd, cwd)
  eq(vim.api.nvim_get_current_buf(), session.buf)
  H.wait(function()
    return output(session):find("CUSTOM:context.lua:2", 1, true) ~= nil
  end)
  eq(output(session):find("renamed.lua", 1, true), nil)
  eq(#pickers, 1)
  eq(notifications, {})
end

T["send without focus can launch in a new tab without another view in the source tab"] = function()
  local origin, source = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local tab = vim.api.nvim_get_current_tabpage()
  gents.send({ "file" }, { focus = false })
  local spec = assert(pickers[1])
  eq(spec.title, "Gents: New Session")
  spec.actions.tabnew(assert(find(spec, "cat")))
  local session = assert(gents.sessions()[1])
  H.wait(function()
    return output(session):find("@context.lua", 1, true) ~= nil
  end)
  eq(vim.api.nvim_get_current_win(), origin)
  eq(vim.api.nvim_get_current_buf(), source)
  eq(vim.api.nvim_tabpage_list_wins(tab), { origin })
  eq(#vim.api.nvim_list_tabpages(), 2)
  local wins = vim.fn.win_findbuf(session.buf)
  eq(#wins, 1)
  eq(vim.api.nvim_win_get_tabpage(assert(wins[1])) == tab, false)
  eq(notifications, {})
end

T["ranged send without sessions supports current-window launch and preserves selected text"] = function()
  local origin = vim.api.nvim_get_current_win()
  vim.cmd("2Gents send")
  local spec = assert(pickers[1])
  eq(spec.title, "Gents: New Session")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed after capture" })
  spec.actions.current(assert(find(spec, "cat")))
  local session = assert(gents.sessions()[1])
  eq(vim.api.nvim_get_current_win(), origin)
  eq(vim.api.nvim_win_get_buf(origin), session.buf)
  eq(vim.api.nvim_tabpage_list_wins(0), { origin })
  H.wait(function()
    return output(session):find("local second = 2", 1, true) ~= nil
  end)
  eq(output(session):find("local first = 1", 1, true), nil)
  eq(output(session):find("changed after capture", 1, true), nil)
  eq(#pickers, 1)
  eq(notifications, {})
end

T["send without sessions can be cancelled"] = test.new_set({
  parametrize = { { "context" }, { "tool" } },
}, {
  ---@param stage string
  ["without creating a session or sending"] = function(stage)
    require("gents.config").get().picker = nil
    ---@type string[]
    local titles = {}
    ---@param items gents.PickerItem<unknown>[]
    ---@param opts vim.ui.select.Opts
    ---@param callback fun(item: gents.PickerItem<unknown>?, idx?: integer)
    set_select(function(items, opts, callback)
      titles[#titles + 1] = assert(opts.prompt)
      if stage == "tool" and opts.prompt == "Gents: Send Context" then
        for _, item in ipairs(items) do
          if item.text:match("^%S+") == "file" then
            callback(item)
            return
          end
        end
        error("Expected file context")
      end
      callback(nil)
    end)
    gents.send()
    eq(
      titles,
      stage == "tool" and { "Gents: Send Context", "Gents: New Session" }
        or { "Gents: Send Context" }
    )
    eq(gents.sessions(), {})
    eq(notifications, {})
  end,
})

T["unavailable context and explicit missing targets do not offer a new session"] = function()
  eq(gents.send({ "selection" }), nil)
  eq(#notifications, 1)
  eq(notifications[1]:find("requested context is not available", 1, true) ~= nil, true)
  test.expect.error(function()
    gents.send({ "file" }, { target = "missing session" })
  end, "no session matches target missing session")
  eq(#pickers, 0)
  eq(gents.sessions(), {})
end

T["composed ranged send with an explicit multiword target"] = test.new_set({
  parametrize = { { true }, { false } },
}, {
  ---@param focus boolean
  ["focuses by default and accepts --no-focus"] = function(focus)
    local origin = vim.api.nvim_get_current_win()
    local selected = H.new({ label = "code review" })
    local other = H.new()
    vim.api.nvim_set_current_win(origin)
    vim.cmd("2Gents actions send " .. (focus and "" or "--no-focus ") .. "--target code review")
    H.wait(function()
      return output(selected):find("local second = 2", 1, true) ~= nil
    end)
    eq(output(selected):find("local first = 1", 1, true), nil)
    eq(output(other):find("local second = 2", 1, true), nil)
    eq(#pickers, 0)
    eq(vim.api.nvim_get_current_buf() == selected.buf, focus)
    eq(vim.api.nvim_get_current_win() == origin, not focus)
  end,
})

T["ranged actions keeps its original selection across picker changes"] = function()
  local origin, source = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  vim.cmd("2Gents actions")
  local menu = assert(pickers[1])
  eq(menu.title, "Gents: Actions")
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "changed after capture" })
  vim.cmd("new")
  choose(menu, "send")
  H.wait(function()
    return output(session):find("local second = 2", 1, true) ~= nil
  end)
  eq(output(session):find("changed after capture", 1, true), nil)
  eq(#pickers, 1)
  eq(vim.api.nvim_get_current_buf(), session.buf)
end

T["actions from a session"] = test.new_set({ parametrize = { { false }, { true } } }, {
  ---@param ranged boolean
  ["rejects send after picker focus changes"] = function(ranged)
    local session = H.new()
    local origin = vim.api.nvim_get_current_win()
    vim.cmd(ranged and "1Gents actions" or "Gents actions")
    local menu = assert(pickers[1])
    eq(menu.title, "Gents: Actions")
    vim.cmd("new")
    choose(menu, "send")
    eq(notifications, { "gents.nvim: send context from a non-session buffer" })
    eq(#pickers, 1)
    eq(vim.api.nvim_get_current_win(), origin)
    eq(vim.api.nvim_get_current_buf(), session.buf)
    eq(gents.sessions(), { session })
  end,
})

T["ranged actions can send captured editor context after its window displays a session"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  vim.cmd("2Gents actions")
  vim.api.nvim_win_set_buf(origin, session.buf)
  choose(assert(pickers[1]), "send")
  H.wait(function()
    return output(session):find("local second = 2", 1, true) ~= nil
  end)
  eq(notifications, {})
  eq(#pickers, 1)
end

T["ranged actions rejects a non-send choice before changing sessions"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  vim.cmd("2Gents actions")
  test.expect.error(function()
    choose(assert(pickers[1]), "hide")
  end, "only send accepts a range")
  eq(require("gents.window").visible(session), true)
  eq(gents.sessions(), { session })
  eq(#pickers, 1)
end

T["exited targets are rejected before showing a window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ cmd = { "sh", "-c", "exit 1" } })
  H.wait(function()
    return session.state == "exited"
  end)
  gents.hide(session.id)
  vim.api.nvim_set_current_win(origin)
  gents.send({ "file" }, { target = session.id })
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(#notifications, 1)
  eq(notifications[1]:find("exited session", 1, true) ~= nil, true)
  eq(vim.api.nvim_get_current_win(), origin)
end

return T
