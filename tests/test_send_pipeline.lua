local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local eq = test.expect.equality
local original_notify = vim.notify
---@param callback fun(message: string, level?: integer, opts?: table)
local function set_notify(callback)
  vim.notify = callback
end
---@type agents.PickerSpec<unknown>[]
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
      agents.setup({
        tools = { cat = { cmd = { "sh", "-c", "printf '1\\n2\\n3\\n4\\n5\\n6\\n'; exec cat" } } },
        prompts = {
          explain = { { text = "Explain:" }, { any = { "selection", "line" } } },
          selected = { "selection" },
        },
        ---@param spec agents.PickerSpec<unknown>
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
      H.reset()
      vim.fn.delete(temp_dir, "d")
    end,
  },
})

---@param session agents.Session
---@return string
local function output(session)
  return table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
end

---@param spec agents.PickerSpec<unknown>
---@param prefix string
---@return agents.PickerItem<unknown>?
local function find(spec, prefix)
  for _, item in ipairs(spec.items) do
    if vim.startswith(item.text, prefix) then
      return item
    end
  end
end

---@param spec agents.PickerSpec<unknown>
---@param prefix string
local function choose(spec, prefix)
  spec.actions[spec.default](assert(find(spec, prefix)))
end

T["send to a hidden target"] = test.new_set({ parametrize = { { true }, { false } } }, {
  ---@param focus boolean
  ["honors focus without disturbing source cursor or later navigation"] = function(focus)
    local origin = vim.api.nvim_get_current_win()
    local session = H.new()
    agents.hide(session.id)
    vim.api.nvim_set_current_win(origin)
    local cursor = vim.api.nvim_win_get_cursor(origin)
    ---@type agents.SendOptions
    local opts = { target = session.id }
    if not focus then
      opts.focus = false
    end
    eq(agents.send({ "line" }, opts), session)
    eq(vim.api.nvim_get_current_buf() == session.buf, focus)
    eq(vim.api.nvim_get_current_win() == origin, not focus)
    eq(vim.api.nvim_win_get_cursor(origin), cursor)
    eq(require("agents.window").visible(session), true)
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
  agents.send({ "file" }, { target = session.id })
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
  agents.send({ "line" }, { target = session.id })
  eq(vim.api.nvim_get_current_buf(), session.buf)
  H.wait(function()
    return output(session):find("CUSTOM:context.lua:2", 1, true) ~= nil
  end)
end

T["context picker omits unavailable providers and prompts and previews defaults"] = function()
  agents.send()
  local spec = assert(pickers[1])
  eq(spec.title, "Agents: send context")
  eq(assert(find(spec, "file —")).preview, "@context.lua")
  eq(find(spec, "selection —"), nil)
  eq(find(spec, "selected [prompt]"), nil)
  eq(assert(find(spec, "explain [prompt]")).preview, "Explain:\n@context.lua:2")
end

T["two asynchronous send pickers"] = test.new_set({ parametrize = { { true }, { false } } }, {
  ---@param focus boolean
  ["preserve the original parts and honor focus after selecting a target"] = function(focus)
    local origin = vim.api.nvim_get_current_win()
    local source = vim.api.nvim_get_current_buf()
    local first = H.new()
    agents.hide(first.id)
    local second = H.new()
    agents.hide(second.id)
    vim.api.nvim_set_current_win(origin)
    agents.send(nil, focus and {} or { focus = false })
    eq(vim.api.nvim_get_current_win(), origin)
    local context_picker = assert(pickers[1])
    local preview = assert(find(context_picker, "buffer —")).preview
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "changed after capture" })
    vim.api.nvim_buf_set_name(source, vim.fs.joinpath(vim.fn.getcwd(), "changed.lua"))
    vim.cmd("new")
    choose(context_picker, "buffer —")
    local target_picker = assert(pickers[2])
    eq(target_picker.title, "Agents: sessions")
    eq(vim.api.nvim_get_current_win(), origin)
    eq(vim.fn.win_findbuf(second.buf), {})
    vim.cmd("new")
    choose(target_picker, second.label .. "  ")
    eq(vim.api.nvim_get_current_buf() == second.buf, focus)
    eq(vim.api.nvim_get_current_win() == origin, not focus)
    H.wait(function()
      return output(second):find("local second = 2", 1, true) ~= nil
    end)
    eq(output(second):find("changed after capture", 1, true), nil)
    eq(output(first):find("local second = 2", 1, true), nil)
    eq(assert(find(context_picker, "buffer —")).preview, preview)
  end,
})

T["target picker cannot change an already resolved provider or source path"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  agents.hide(session.id)
  agents.hide(H.new().id)
  vim.api.nvim_set_current_win(origin)
  agents.send({ "line" })
  local spec = assert(pickers[1])
  vim.api.nvim_buf_set_name(0, vim.fs.joinpath(vim.fn.getcwd(), "renamed.lua"))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.lcd(temp_dir)
  choose(spec, session.label .. "  ")
  eq(vim.api.nvim_get_current_buf(), session.buf)
  H.wait(function()
    return output(session):find("@context.lua:2", 1, true) ~= nil
  end)
end

T["unknown and unavailable items send nothing and do not open target pickers"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  agents.hide(session.id)
  vim.api.nvim_set_current_win(origin)
  test.expect.error(function()
    agents.send({ "file", "missing-provider" })
  end, "unknown provider")
  eq(agents.send({ "file", "selection" }), nil)
  eq(#notifications, 1)
  eq(#pickers, 0)
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(vim.api.nvim_get_current_win(), origin)
end

T["ranged command sends selected lines directly and named prompts expand"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  vim.cmd("2Agents send")
  H.wait(function()
    return output(session):find("local second = 2", 1, true) ~= nil
  end)
  eq(output(session):find("local first = 1", 1, true), nil)
  eq(#pickers, 0)
  eq(vim.api.nvim_get_current_buf(), session.buf)
  vim.cmd("Agents send explain")
  H.wait(function()
    return output(session):find("Explain:", 1, true) ~= nil
  end)
end

T["no sessions gives actionable feedback"] = function()
  agents.send({ "file" })
  eq(#notifications, 1)
  eq(notifications[1]:find(":Agents new", 1, true) ~= nil, true)
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
    vim.cmd("2Agents actions send " .. (focus and "" or "--no-focus ") .. "--target code review")
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
  vim.cmd("2Agents actions")
  local menu = assert(pickers[1])
  eq(menu.title, "Agents: actions")
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

T["ranged actions rejects a non-send choice before changing sessions"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  vim.api.nvim_set_current_win(origin)
  vim.cmd("2Agents actions")
  test.expect.error(function()
    choose(assert(pickers[1]), "hide")
  end, "only send accepts a range")
  eq(require("agents.window").visible(session), true)
  eq(agents.sessions(), { session })
  eq(#pickers, 1)
end

T["exited targets are rejected before showing a window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ cmd = { "sh", "-c", "exit 1" } })
  H.wait(function()
    return session.state == "exited"
  end)
  agents.hide(session.id)
  vim.api.nvim_set_current_win(origin)
  agents.send({ "file" }, { target = session.id })
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(#notifications, 1)
  eq(notifications[1]:find("exited session", 1, true) ~= nil, true)
  eq(vim.api.nvim_get_current_win(), origin)
end

return T
