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
---@alias agents.Picker "snacks"|agents.PickerAdapter

---@param origin integer
---@param kind string
---@return boolean
local function restore_origin(origin, kind)
  if not vim.api.nvim_win_is_valid(origin) then
    vim.notify(
      "agents.nvim: the window that opened the " .. kind .. " picker no longer exists",
      vim.log.levels.ERROR
    )
    return false
  end
  vim.api.nvim_set_current_win(origin)
  return true
end

---@generic T
---@param spec agents.PickerSpec<T>
function M.open(spec)
  local adapter = require("agents.config").get().picker
  if adapter == "snacks" then
    require("agents.pickers.snacks").open(spec)
    return
  elseif adapter then
    adapter(spec)
    return
  end

  vim.ui.select(
    spec.items,
    {
      prompt = spec.title,
      ---@param item { text: string }
      ---@return string
      format_item = function(item)
        return item.text
      end,
    },
    ---@param item? agents.PickerItem<unknown>
    function(item)
      if item then
        spec.actions[spec.default](item)
      end
    end
  )
end

---@param callback fun(command: agents.CommandName)
function M.commands(callback)
  local origin = vim.api.nvim_get_current_win()
  ---@type agents.PickerItem<agents.CommandName>[]
  local items = {}
  for _, command in ipairs(require("agents.commands").names(true)) do
    items[#items + 1] = { text = command, data = command }
  end
  M.open({
    title = "Agents: actions",
    items = items,
    default = "run",
    actions = {
      ---@param item agents.PickerItem<agents.CommandName>
      run = function(item)
        if restore_origin(origin, "actions") then
          callback(item.data)
        end
      end,
    },
  })
end

---@param callback fun(tool: agents.Tool, opts: agents.NewOptions)
---@param opts? agents.NewOptions
function M.tools(callback, opts)
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

  ---@param item agents.PickerItem<agents.Tool>
  ---@param launch_opts agents.NewOptions
  local function launch(item, launch_opts)
    if not restore_origin(origin, "tool") then
      return
    end
    local tool = item.data
    local cmd = launch_opts.cmd or tool.cmd
    if vim.fn.executable(cmd[1]) == 0 then
      vim.notify("agents.nvim: executable not found: " .. cmd[1], vim.log.levels.ERROR)
      if tool.url then
        vim.ui.open(tool.url)
      end
      return
    end
    callback(tool, launch_opts)
  end

  ---@type agents.PickerSpec<agents.Tool>
  local spec = {
    title = "Agents: new session",
    items = items,
    default = "new",
    actions = {
      ---@param item agents.PickerItem<agents.Tool>
      new = function(item)
        launch(item, vim.deepcopy(opts or {}))
      end,
      ---@param item agents.PickerItem<agents.Tool>
      edit_args = function(item)
        if not restore_origin(origin, "tool") then
          return
        end
        local launch_opts = vim.deepcopy(opts or {})
        local cmd = vim.deepcopy(launch_opts.cmd or item.data.cmd)
        vim.list_extend(cmd, launch_opts.args or {})
        vim.ui.input(
          { prompt = "Agents: command: ", default = table.concat(cmd, " ") },
          function(value)
            if value == nil then
              return
            end
            ---@type string[]
            local edited = {}
            for word in value:gmatch("%S+") do
              edited[#edited + 1] = word
            end
            if #edited == 0 then
              vim.notify("agents.nvim: command must not be empty", vim.log.levels.ERROR)
              return
            end
            launch_opts.cmd, launch_opts.args = edited, nil
            launch(item, launch_opts)
          end
        )
      end,
    },
  }
  for _, layout in ipairs({ "vsplit", "split", "tabnew", "current" }) do
    ---@param item agents.PickerItem<agents.Tool>
    spec.actions[layout] = function(item)
      local launch_opts = vim.deepcopy(opts or {})
      launch_opts.layout = layout
      launch(item, launch_opts)
    end
  end
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
    local label = session.label .. (session.title and " · " .. session.title or "")
    local text = label .. "  [" .. state .. "]  " .. session.cwd
    if not vim.deep_equal(session.cmd, session.tool.cmd) then
      text = text .. "  " .. table.concat(session.cmd, " ")
    end
    items[#items + 1] = { text = text, data = session }
  end

  ---@param item agents.PickerItem<agents.Session>
  ---@param action fun(session: agents.Session)
  local function select(item, action)
    local session = require("agents.session").get(item.data.id)
    if session and restore_origin(origin, "session") then
      action(session)
    end
  end

  ---@type agents.PickerSpec<agents.Session>
  local spec = {
    title = "Agents: sessions",
    items = items,
    default = "show",
    actions = {
      ---@param item agents.PickerItem<agents.Session>
      show = function(item)
        select(item, callback)
      end,
      ---@param item agents.PickerItem<agents.Session>
      hide = function(item)
        select(item, window.hide)
      end,
      ---@param item agents.PickerItem<agents.Session>
      close = function(item)
        select(item, require("agents.session").close)
      end,
    },
  }
  for _, layout in ipairs({ "vsplit", "split", "tabnew", "current" }) do
    ---@param item agents.PickerItem<agents.Session>
    spec.actions[layout] = function(item)
      select(item, function(session)
        window.show(session, layout)
      end)
    end
  end
  M.open(spec)
end

---@param ctx agents.Context
---@param callback fun(parts: agents.Part[])
function M.context(ctx, callback)
  local origin = vim.api.nvim_get_current_win()
  local render = require("agents.render")
  local providers = require("agents.providers")
  ---@type agents.PickerItem<agents.Part[]>[]
  local items = {}

  ---@param label string
  ---@param source agents.Item[]
  local function add(label, source)
    local parts = render.resolve(source, ctx)
    if parts then
      items[#items + 1] = { text = label, preview = render.text(parts, ctx), data = parts }
    end
  end

  local prompts = require("agents.config").get().prompts
  ---@type string[]
  local names = vim.tbl_keys(prompts)
  table.sort(names)
  for _, name in ipairs(names) do
    add(name .. " [prompt]", prompts[name])
  end
  for _, name in ipairs(providers.names()) do
    add(name .. " — " .. assert(providers.get(name)).desc, { name })
  end

  M.open({
    title = "Agents: send context",
    items = items,
    default = "send",
    actions = {
      ---@param item agents.PickerItem<agents.Part[]>
      send = function(item)
        if restore_origin(origin, "context") then
          callback(item.data)
        end
      end,
    },
  })
end

return M
