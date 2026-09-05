local M = {}

---@class agents.PickerItem<T>
---@field text string
---@field preview? string
---@field data T
---@field hl? string Suggested highlight group for adapters that support item styling.

---@class agents.PickerSpec<T>
---@field title string
---@field items agents.PickerItem<T>[]
---@field actions table<string, fun(item: agents.PickerItem<T>)>
---@field default string Action name used for Enter.

---@alias agents.PickerAdapter fun<T>(spec: agents.PickerSpec<T>)

---@generic T
---@param spec agents.PickerSpec<T>
function M.open(spec)
  local adapter = require("agents.config").get().picker
  if adapter then
    adapter(spec)
    return
  end

  vim.ui.select(spec.items, {
    prompt = spec.title,
    ---@param item { text: string }
    ---@return string
    format_item = function(item)
      return item.text
    end,
  }, function(item)
    if item then
      spec.actions[spec.default](item)
    end
  end)
end

---@param callback fun(tool: agents.Tool)
function M.tools(callback)
  local config = require("agents.config").get()
  local origin = vim.api.nvim_get_current_win()
  ---@type agents.PickerItem<agents.Tool>[]
  local items = {}
  for _, name in ipairs(require("agents.tools").names(config.tools)) do
    local tool = config.tools[name]
    if tool.enabled ~= false then
      local missing = vim.fn.executable(tool.cmd[1]) == 0
      items[#items + 1] = {
        text = name .. (missing and " [not installed]" or ""),
        data = tool,
        hl = missing and "Comment" or nil,
      }
    end
  end

  ---@type agents.PickerSpec<agents.Tool>
  local spec = {
    title = "Agents: new session",
    items = items,
    default = "new",
    actions = {
      ---@param item agents.PickerItem<agents.Tool>
      new = function(item)
        if not vim.api.nvim_win_is_valid(origin) then
          vim.notify(
            "agents.nvim: the window that opened the tool picker no longer exists",
            vim.log.levels.ERROR
          )
          return
        end
        vim.api.nvim_set_current_win(origin)
        local tool = item.data
        if vim.fn.executable(tool.cmd[1]) == 0 then
          vim.notify("agents.nvim: executable not found: " .. tool.cmd[1], vim.log.levels.ERROR)
          if tool.url then
            vim.ui.open(tool.url)
          end
          return
        end
        callback(tool)
      end,
    },
  }
  M.open(spec)
end

---@param candidates agents.Session[]
---@param callback fun(session: agents.Session)
function M.sessions(candidates, callback)
  local window = require("agents.window")
  local tab = vim.api.nvim_get_current_tabpage()
  local origin = vim.api.nvim_get_current_win()
  ---@type agents.Session[]
  local ordered = {}
  ---@type table<integer, integer>
  local ranks = {}
  for _, session in ipairs(candidates) do
    ordered[#ordered + 1] = session
    local hidden_here = session.tab == tab and not window.visible(session)
    ranks[session.id] = window.visible(session, tab) and 1 or (hidden_here and 2 or 3)
  end
  table.sort(ordered, function(a, b)
    if ranks[a.id] ~= ranks[b.id] then
      return ranks[a.id] < ranks[b.id]
    end
    return a.id < b.id
  end)

  ---@type agents.PickerItem<agents.Session>[]
  local items = {}
  for _, session in ipairs(ordered) do
    local state = session.state == "exited" and "exited"
      or (window.visible(session) and "visible" or "hidden")
    local text = session.label .. "  [" .. state .. "]  " .. session.cwd
    if not vim.deep_equal(session.cmd, session.tool.cmd) then
      text = text .. "  " .. table.concat(session.cmd, " ")
    end
    items[#items + 1] = { text = text, data = session }
  end

  ---@type agents.PickerSpec<agents.Session>
  local spec = {
    title = "Agents: sessions",
    items = items,
    default = "show",
    actions = {
      ---@param item agents.PickerItem<agents.Session>
      show = function(item)
        local session = require("agents.session").get(item.data.id)
        if not session then
          return
        end
        if not vim.api.nvim_win_is_valid(origin) then
          vim.notify(
            "agents.nvim: the window that opened the session picker no longer exists",
            vim.log.levels.ERROR
          )
          return
        end
        vim.api.nvim_set_current_win(origin)
        callback(session)
      end,
    },
  }
  M.open(spec)
end

return M
