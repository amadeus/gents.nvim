local M = {}

-- Only the mini.pick surface used by this adapter is described here, so
-- mini.pick remains optional and its type definitions are not required by LuaLS.
---@class agents.pickers.MiniItem
---@field text string
---@field agents_index integer

---@class agents.pickers.MiniMapping
---@field char string
---@field func fun(): boolean?

---@alias agents.pickers.MiniMappings table<string, string|agents.pickers.MiniMapping>

---@class agents.pickers.MiniSource
---@field name string
---@field items agents.pickers.MiniItem[]
---@field show fun(buf: integer, items: agents.pickers.MiniItem[], query: string[])
---@field choose fun(item: agents.pickers.MiniItem): boolean?

---@class agents.pickers.MiniOptions
---@field source agents.pickers.MiniSource
---@field mappings agents.pickers.MiniMappings

---@class agents.pickers.MiniPick
---@field config { mappings: agents.pickers.MiniMappings }
---@field start fun(opts: agents.pickers.MiniOptions)
---@field default_show fun(buf: integer, items: agents.pickers.MiniItem[], query: string[])
---@field get_picker_matches fun(): { current?: agents.pickers.MiniItem }?
---@field get_picker_state fun(): { windows: { target: integer } }?
---@field is_picker_active fun(): boolean

---Built-in mini.pick placement actions replaced by agents.nvim placement, keyed
---by the agents.nvim action that takes over their key.
---@type table<string, string>
local native = {
  vsplit = "choose_in_vsplit",
  split = "choose_in_split",
  tabnew = "choose_in_tabpage",
}

---Adapter actions in binding order: agents.nvim action, the mapping name shown
---in the info view, and the key for actions without a mini.pick counterpart.
---Names carry a prefix so they never replace a user's own custom mappings.
---@type { [1]: string, [2]: string, [3]?: string }[]
local bindings = {
  { "vsplit", "agents_open_in_vsplit" },
  { "split", "agents_open_in_split" },
  { "tabnew", "agents_open_in_tabpage" },
  { "float", "agents_open_in_float", "<M-f>" },
  { "current", "agents_open_here", "<C-CR>" },
  { "edit_args", "agents_edit_command", "<C-e>" },
  { "hide", "agents_hide_session", "<M-h>" },
  { "close", "agents_close_session", "<C-d>" },
}

local namespace = vim.api.nvim_create_namespace("agents.pickers.mini")

---mini.pick must be set up before use, as its integration guide recommends.
---@return agents.pickers.MiniPick?
function M.instance()
  ---@type agents.pickers.MiniPick?
  local mini = rawget(_G, "MiniPick")
  return mini
end

---The window an active mini.pick picker returns to. A menu requested from a
---mini.pick action returns there rather than to the picker window.
---@return integer?
function M.origin()
  local mini = M.instance()
  if mini and mini.is_picker_active() then
    local state = mini.get_picker_state()
    return state and state.windows.target
  end
  return nil
end

---@param key string
---@return string
local function termcodes(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

---@param mapping string|agents.pickers.MiniMapping
---@return string
local function mapping_key(mapping)
  if type(mapping) == "string" then
    return mapping
  end
  return mapping.char
end

---The mappings mini.pick resolves for a picker started from the current buffer.
---@param mini agents.pickers.MiniPick
---@return agents.pickers.MiniMappings
local function configured_mappings(mini)
  ---@type { mappings?: agents.pickers.MiniMappings }?
  local buffer = vim.b.minipick_config
  return vim.tbl_deep_extend("force", mini.config.mappings, buffer and buffer.mappings or {})
end

---@param text string
---@return integer Byte length of text as MiniPick.default_show renders it.
local function rendered_length(text)
  local rendered =
    text:gsub("%z", "│"):gsub("[\r\n]", " "):gsub("\t", string.rep(" ", vim.o.tabstop))
  return #rendered
end

---@generic T
---@param spec agents.PickerSpec<T>
function M.open(spec)
  local mini = M.instance()
  if not mini then
    vim.notify(
      'agents.nvim: picker = "mini" requires mini.pick; install mini.nvim or mini.pick and call require("mini.pick").setup()',
      vim.log.levels.ERROR
    )
    return
  end
  if mini.is_picker_active() then
    -- Like MiniPick.ui_select, wait for the active picker instead of interrupting it.
    vim.api.nvim_create_autocmd("User", {
      pattern = "MiniPickStop",
      once = true,
      callback = vim.schedule_wrap(function()
        M.open(spec)
      end),
    })
    return
  end

  local shared = require("agents.picker")
  ---@type agents.pickers.MiniItem[]
  local items = {}
  for index, item in ipairs(spec.items) do
    items[index] = { text = item.text, agents_index = index }
  end
  ---@type { action: string, index: integer }?
  local pending

  ---@param action string
  ---@param item? agents.pickers.MiniItem
  local function request(action, item)
    if item then
      pending = { action = action, index = item.agents_index }
    end
  end

  -- Keys used by the configured mini.pick mappings stay theirs, except the
  -- placement actions that agents.nvim provides itself.
  local configured = configured_mappings(mini)
  ---@type table<string, boolean>
  local rerouted = {}
  for _, name in pairs(native) do
    rerouted[name] = true
  end
  ---@type table<string, boolean>
  local taken = {}
  for name, mapping in pairs(configured) do
    if not rerouted[name] then
      taken[termcodes(mapping_key(mapping))] = true
    end
  end
  -- Menus act on one row and have no preview, so marking and previews are off.
  ---@type agents.pickers.MiniMappings
  local mappings = {
    choose_in_split = "",
    choose_in_tabpage = "",
    choose_in_vsplit = "",
    choose_marked = "",
    mark = "",
    mark_all = "",
    refine_marked = "",
    toggle_preview = "",
  }
  for _, binding in ipairs(bindings) do
    local action, name = binding[1], binding[2]
    local char = binding[3]
    if not char then
      local placement = configured[assert(native[action])]
      char = type(placement) == "string" and placement or ""
    end
    local key = termcodes(char)
    if spec.actions[action] and key ~= "" and not taken[key] then
      taken[key] = true
      mappings[name] = {
        char = char,
        func = function()
          local matches = mini.get_picker_matches()
          request(action, matches and matches.current)
          return true
        end,
      }
    end
  end

  mini.start({
    source = {
      name = spec.title,
      items = items,
      show = function(buf, shown, query)
        mini.default_show(buf, shown, query)
        vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
        for row, item in ipairs(shown) do
          local source = spec.items[item.agents_index]
          local col = 0
          for _, chunk in ipairs(source.chunks or { { text = source.text } }) do
            local length = rendered_length(chunk.text)
            local group = chunk.kind and shared.chunk_highlights[chunk.kind] or source.hl
            if group and length > 0 then
              pcall(vim.api.nvim_buf_set_extmark, buf, namespace, row - 1, col, {
                end_col = col + length,
                hl_group = group,
                -- Below mini.pick's match, current, and marked highlights.
                priority = 100,
              })
            end
            col = col + length
          end
        end
      end,
      choose = function(item)
        request(spec.default, item)
      end,
    },
    mappings = mappings,
  })
  -- mini.pick has restored the target window once start() returns.
  if pending then
    local action = assert(spec.actions[pending.action])
    action(spec.items[pending.index])
  end
end

return M
