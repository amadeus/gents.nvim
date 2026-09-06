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

T["send shows a hidden target while preserving source window and cursor"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  agents.hide(session.id)
  vim.api.nvim_set_current_win(origin)
  local cursor = vim.api.nvim_win_get_cursor(origin)
  eq(agents.send({ "line" }, { target = session.id }), session)
  eq(vim.api.nvim_get_current_win(), origin)
  eq(vim.api.nvim_win_get_cursor(origin), cursor)
  eq(require("agents.window").visible(session, vim.api.nvim_get_current_tabpage()), true)
  H.wait(function()
    return output(session):find("@context.lua:2", 1, true) ~= nil
  end)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["a target visible in another tab gets a view in the invoking tab"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  vim.api.nvim_set_current_win(origin)
  local tab = vim.api.nvim_get_current_tabpage()
  agents.send({ "file" }, { target = session.id })
  eq(vim.api.nvim_get_current_win(), origin)
  eq(vim.api.nvim_get_current_tabpage(), tab)
  eq(#vim.fn.win_findbuf(session.buf), 2)
  H.wait(function()
    return output(session):find("@context.lua", 1, true) ~= nil
  end)
end

T["focus is opt in and target locations use the captured source cwd"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ layout = "tabnew" })
  session.tool.location = function(path, range)
    return "CUSTOM:" .. path .. ":" .. assert(range).start[1]
  end
  vim.api.nvim_set_current_win(origin)
  agents.send({ "line" }, { target = session.id, focus = true })
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

T["two asynchronous pickers keep the original parts and invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local source = vim.api.nvim_get_current_buf()
  local first = H.new()
  agents.hide(first.id)
  local second = H.new()
  agents.hide(second.id)
  vim.api.nvim_set_current_win(origin)
  agents.send()
  local context_picker = assert(pickers[1])
  local preview = assert(find(context_picker, "buffer —")).preview
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "changed after capture" })
  vim.api.nvim_buf_set_name(source, vim.fs.joinpath(vim.fn.getcwd(), "changed.lua"))
  vim.cmd("new")
  choose(context_picker, "buffer —")
  local target_picker = assert(pickers[2])
  eq(target_picker.title, "Agents: sessions")
  vim.cmd("new")
  choose(target_picker, second.label .. "  ")
  eq(vim.api.nvim_get_current_win(), origin)
  H.wait(function()
    return output(second):find("local second = 2", 1, true) ~= nil
  end)
  eq(output(second):find("changed after capture", 1, true), nil)
  eq(output(first):find("local second = 2", 1, true), nil)
  eq(assert(find(context_picker, "buffer —")).preview, preview)
end

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
end

return T
