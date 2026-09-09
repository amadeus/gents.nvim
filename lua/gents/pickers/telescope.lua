local M = {}

-- Only the Telescope surface used by this adapter is described here, so
-- Telescope remains optional and its type definitions are not required by LuaLS.
---@alias agents.pickers.TelescopeHighlight { [1]: { [1]: integer, [2]: integer }, [2]: string }

---@class agents.pickers.TelescopeEntry
---@field value agents.PickerItem<unknown>
---@field ordinal string
---@field display fun(): string, agents.pickers.TelescopeHighlight[]

---@alias agents.pickers.TelescopeMapping string|boolean|table|fun(prompt_bufnr: integer)
---@alias agents.pickers.TelescopeMap fun(modes: string|string[], key: string, callback: agents.pickers.TelescopeMapping, opts?: { desc: string })

---@class agents.pickers.TelescopeOptions
---@field prompt_title string
---@field finder table
---@field sorter table
---@field previewer false
---@field attach_mappings fun(prompt_bufnr: integer, map: agents.pickers.TelescopeMap): boolean

---@class agents.pickers.TelescopePicker
---@field find fun(self: agents.pickers.TelescopePicker)

---@class agents.pickers.TelescopePickers
---@field new fun(opts: table, defaults: agents.pickers.TelescopeOptions): agents.pickers.TelescopePicker

---@class agents.pickers.TelescopeTableFinder
---@field results agents.PickerItem<unknown>[]
---@field entry_maker fun(item: agents.PickerItem<unknown>): agents.pickers.TelescopeEntry

---@class agents.pickers.TelescopeFinders
---@field new_table fun(opts: agents.pickers.TelescopeTableFinder): table

---@class agents.pickers.TelescopeConfigValues
---@field generic_sorter fun(opts: table): table
---@field mappings table<string, table<string, agents.pickers.TelescopeMapping>>
---@field default_mappings? table<string, table<string, agents.pickers.TelescopeMapping>>

---@class agents.pickers.TelescopeConfig
---@field values agents.pickers.TelescopeConfigValues

---@class agents.pickers.TelescopeActions
---@field close fun(prompt_bufnr: integer)
---@field nop fun(prompt_bufnr: integer)

---@class agents.pickers.TelescopeReplaceable
---@field replace fun(self: agents.pickers.TelescopeReplaceable, callback: fun(prompt_bufnr: integer, kind: string))

---@class agents.pickers.TelescopeActionSet
---@field select agents.pickers.TelescopeReplaceable

---@class agents.pickers.TelescopeCurrentPicker
---@field original_win_id integer

---@class agents.pickers.TelescopeActionState
---@field get_selected_entry fun(): agents.pickers.TelescopeEntry?
---@field get_current_picker fun(prompt_bufnr: integer): agents.pickers.TelescopeCurrentPicker?

---@class agents.pickers.TelescopeModules
---@field pickers agents.pickers.TelescopePickers
---@field finders agents.pickers.TelescopeFinders
---@field config agents.pickers.TelescopeConfig
---@field actions agents.pickers.TelescopeActions
---@field action_set agents.pickers.TelescopeActionSet
---@field action_state agents.pickers.TelescopeActionState

---agents.nvim actions run by Telescope's select types, besides the default.
---@type table<string, string>
local selections = { horizontal = "split", vertical = "vsplit", tab = "tabnew" }

---Adapter actions in binding order: agents.nvim action, the description shown
---by Telescope's key hints, and the key for both Insert and Normal mode.
---@type { [1]: string, [2]: string, [3]: string }[]
local bindings = {
  { "vsplit", "agents_open_in_vsplit", "<C-v>" },
  { "split", "agents_open_in_split", "<C-x>" },
  { "tabnew", "agents_open_in_tab", "<C-t>" },
  { "float", "agents_open_in_float", "<C-f>" },
  { "current", "agents_open_here", "<C-CR>" },
  { "edit_args", "agents_edit_command", "<C-e>" },
  { "hide", "agents_hide_session", "<M-h>" },
  { "close", "agents_close_session", "<C-d>" },
}

---Default Telescope keys whose actions treat rows as files or multi selections.
---@type string[]
local disabled = { "<Tab>", "<S-Tab>", "<C-q>", "<M-q>" }

---Telescope needs no setup call; its modules load on first use. Loading them
---also requires plenary.nvim, so a missing dependency is reported the same way.
---@return agents.pickers.TelescopeModules?
function M.instance()
  ---@type agents.pickers.TelescopeModules?
  local modules
  local ok = pcall(function()
    modules = {
      pickers = require("telescope.pickers"),
      finders = require("telescope.finders"),
      config = require("telescope.config"),
      actions = require("telescope.actions"),
      action_set = require("telescope.actions.set"),
      action_state = require("telescope.actions.state"),
    }
  end)
  return ok and modules or nil
end

---The window an active Telescope prompt returns to. A menu requested from a
---Telescope mapping returns there rather than to the prompt window.
---@return integer?
function M.origin()
  if vim.bo.filetype ~= "TelescopePrompt" then
    return nil
  end
  local telescope = M.instance()
  local picker = telescope
    and telescope.action_state.get_current_picker(vim.api.nvim_get_current_buf())
  return picker and picker.original_win_id
end

---@param key string
---@return string
local function termcodes(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

---@generic T
---@param spec agents.PickerSpec<T>
function M.open(spec)
  local telescope = M.instance()
  if not telescope then
    vim.notify(
      'agents.nvim: picker = "telescope" requires telescope.nvim and plenary.nvim; install nvim-telescope/telescope.nvim and nvim-lua/plenary.nvim',
      vim.log.levels.ERROR
    )
    return
  end
  local shared = require("agents.picker")

  -- Keys in the user's Telescope mappings stay theirs, including disabled ones,
  -- whether they extend or replace the base mappings.
  ---@type table<string, table<string, boolean>>
  local configured = { i = {}, n = {} }
  local values = telescope.config.values
  for _, source in ipairs({ values.mappings, values.default_mappings or {} }) do
    for mode, mappings in pairs(source) do
      mode = mode:lower()
      configured[mode] = configured[mode] or {}
      for key in pairs(mappings) do
        configured[mode][termcodes(key)] = true
      end
    end
  end

  ---@param mode string
  ---@param key string
  ---@return boolean
  local function free(mode, key)
    return not configured[mode][termcodes(key)]
  end

  telescope.pickers
    .new({}, {
      prompt_title = spec.title,
      finder = telescope.finders.new_table({
        results = spec.items,
        entry_maker = function(item)
          return {
            value = item,
            ordinal = item.text,
            display = function()
              ---@type agents.pickers.TelescopeHighlight[]
              local highlights = {}
              local col = 0
              for _, chunk in ipairs(item.chunks or { { text = item.text } }) do
                local group = chunk.kind and shared.chunk_highlights[chunk.kind] or item.hl
                if group and #chunk.text > 0 then
                  highlights[#highlights + 1] = { { col, col + #chunk.text }, group }
                end
                col = col + #chunk.text
              end
              return item.text, highlights
            end,
          }
        end,
      }),
      sorter = telescope.config.values.generic_sorter({}),
      previewer = false,
      attach_mappings = function(prompt_bufnr, map)
        ---@param name string
        local function run(name)
          local action = spec.actions[name]
          local entry = telescope.action_state.get_selected_entry()
          if not action or not entry then
            return
          end
          local item = entry.value
          telescope.actions.close(prompt_bufnr)
          -- Telescope has restored the original window; run outside its keymap.
          vim.schedule(function()
            action(item)
          end)
        end

        -- Enter and every key bound to a Telescope select action run agents.nvim
        -- actions instead of opening rows as files.
        telescope.action_set.select:replace(function(_, kind)
          run(kind == "default" and spec.default or selections[kind] or "")
        end)
        for _, binding in ipairs(bindings) do
          local action, desc, key = binding[1], binding[2], binding[3]
          for _, mode in ipairs({ "i", "n" }) do
            if spec.actions[action] and free(mode, key) then
              map(mode, key, function()
                run(action)
              end, { desc = desc })
            end
          end
        end
        -- Menus act on one row; multi selection and quickfix keys do nothing.
        for _, key in ipairs(disabled) do
          for _, mode in ipairs({ "i", "n" }) do
            if free(mode, key) then
              map(mode, key, telescope.actions.nop)
            end
          end
        end
        return true
      end,
    })
    :find()
end

return M
