local M = {}

-- Only the fzf-lua surface used by this adapter is described here, so fzf-lua
-- remains optional and its type definitions are not required by LuaLS.
---@class gents.pickers.FzfAction
---@field fn fun(selected: string[])
---@field desc string

---@class gents.pickers.FzfOptions
---@field winopts { title: string }
---@field previewer false
---@field fzf_opts table<string, string|boolean>
---@field actions table<string, gents.pickers.FzfAction>

---@class gents.pickers.FzfKeymap
---@field fzf? table<string, string|boolean|table|function>
---@field builtin? table<string, string|boolean>

---@class gents.pickers.FzfModules
---@field fzf_exec fun(contents: string[], opts: gents.pickers.FzfOptions)
---@field ansi_from_hl fun(group: string, text: string): string
---@field keymap gents.pickers.FzfKeymap
---@field fzf_bin? string The configured executable, before fzf-lua's fallbacks.

---Adapter actions in binding order: gents.nvim action, the description shown
---by fzf-lua's help window, and the fzf key name.
---@type { [1]: string, [2]: string, [3]: string }[]
local bindings = {
  { "vsplit", "gents-open-in-vsplit", "ctrl-v" },
  { "split", "gents-open-in-split", "ctrl-s" },
  { "tabnew", "gents-open-in-tab", "ctrl-t" },
  { "float", "gents-open-in-float", "alt-f" },
  { "current", "gents-open-here", "alt-enter" },
  { "edit_args", "gents-edit-command", "alt-e" },
  { "hide", "gents-hide-session", "alt-h" },
  { "close", "gents-close-session", "ctrl-x" },
}

---Help names for each menu's default action.
---@type table<string, string>
local labels = { new = "start", show = "show", run = "run", send = "send" }

---fzf-lua needs no setup call; its modules load on first use.
---@return gents.pickers.FzfModules?
function M.instance()
  ---@type gents.pickers.FzfModules?
  local modules
  local ok = pcall(function()
    ---@type { fzf_exec: fun(contents: string[], opts: gents.pickers.FzfOptions) }
    local fzf = require("fzf-lua")
    ---@type { globals: { keymap: gents.pickers.FzfKeymap, fzf_bin?: string } }
    local config = require("fzf-lua.config")
    ---@type { ansi_from_hl: fun(group: string, text: string): string }
    local utils = require("fzf-lua.utils")
    modules = {
      fzf_exec = fzf.fzf_exec,
      ansi_from_hl = utils.ansi_from_hl,
      keymap = config.globals.keymap,
      fzf_bin = config.globals.fzf_bin,
    }
  end)
  return ok and modules or nil
end

---The executable fzf-lua will run: the configured binary, then fzf on PATH,
---then fzf.vim's download, following fzf-lua's own fallback order.
---@param modules gents.pickers.FzfModules
---@return string?
function M.binary(modules)
  local configured = modules.fzf_bin and vim.fn.expand(modules.fzf_bin) or nil
  if configured and vim.fn.executable(configured) == 1 then
    return configured
  end
  if vim.fn.executable("fzf") == 1 then
    return "fzf"
  end
  local ok, plugin = pcall(vim.api.nvim_call_function, "fzf#exec", {})
  if ok and type(plugin) == "string" and vim.fn.executable(plugin) == 1 then
    return plugin
  end
  return nil
end

---fzf's name for a key in fzf-lua's keymaps. Alt with a single letter is case
---sensitive in fzf; everything else compares in lowercase.
---@param key string
---@return string
local function fzf_key(key)
  local name = key:gsub("[<>]", "")
  local letter = name:match("^[mMaA]%-(%a)$") or name:match("^[aA][lL][tT]%-(%a)$")
  if letter then
    return "alt-" .. letter
  end
  name = name:lower()
  for _, modifier in ipairs({ { "c", "ctrl" }, { "m", "alt" }, { "a", "alt" }, { "s", "shift" } }) do
    name = name:gsub("^" .. modifier[1] .. "%-", modifier[2] .. "-")
  end
  return (name:gsub("cr$", "enter"))
end

---@generic T
---@param spec gents.PickerSpec<T>
function M.open(spec)
  local modules = M.instance()
  if not modules then
    vim.notify(
      'gents.nvim: picker = "fzf-lua" requires fzf-lua; install ibhagwan/fzf-lua and the fzf executable',
      vim.log.levels.ERROR
    )
    return
  end
  if not M.binary(modules) then
    vim.notify(
      'gents.nvim: picker = "fzf-lua" requires the fzf executable; install fzf or set fzf_bin in fzf-lua ('
        .. (modules.fzf_bin or "fzf")
        .. " was not found)",
      vim.log.levels.ERROR
    )
    return
  end
  local shared = require("gents.picker")

  -- Rows carry their index in a hidden first field, so the selected line maps
  -- back to the original item while fzf matches only the visible text.
  ---@type string[]
  local lines = {}
  for index, item in ipairs(spec.items) do
    ---@type string[]
    local parts = {}
    for _, chunk in ipairs(item.chunks or { { text = item.text } }) do
      local group = chunk.kind and shared.chunk_highlights[chunk.kind] or item.hl
      parts[#parts + 1] = group and modules.ansi_from_hl(group, chunk.text) or chunk.text
    end
    lines[index] = index .. "\t" .. table.concat(parts)
  end

  ---@param name string
  ---@return fun(selected: string[])
  local function run(name)
    return function(selected)
      local action = spec.actions[name]
      local index = selected[1] and tonumber(selected[1]:match("^(%d+)\t"))
      local item = index and spec.items[index]
      if action and item then
        -- fzf-lua has closed its window and restored the previous window.
        action(item)
      end
    end
  end

  -- Keys in the user's fzf-lua keymaps stay theirs, including disabled ones.
  -- Enter always runs the default action, as in fzf-lua's own pickers.
  ---@type table<string, boolean>
  local taken = {}
  for key in pairs(modules.keymap.fzf or {}) do
    taken[fzf_key(key)] = true
  end
  for key in pairs(modules.keymap.builtin or {}) do
    taken[fzf_key(key)] = true
  end
  ---@type table<string, gents.pickers.FzfAction>
  local actions = {
    enter = { fn = run(spec.default), desc = "gents-" .. (labels[spec.default] or spec.default) },
  }
  for _, binding in ipairs(bindings) do
    local action, desc, key = binding[1], binding[2], binding[3]
    if spec.actions[action] and not taken[key] then
      actions[key] = { fn = run(action), desc = desc }
    end
  end

  modules.fzf_exec(lines, {
    winopts = { title = " " .. spec.title .. " " },
    previewer = false,
    -- Inherited field and preview options would break the hidden index or show
    -- a preview, so the ones this adapter relies on are pinned here.
    fzf_opts = {
      ["--ansi"] = true,
      ["--delimiter"] = "\t",
      ["--with-nth"] = "2..",
      ["--nth"] = false,
      ["--accept-nth"] = false,
      ["--multi"] = false,
      ["--no-multi"] = true,
      ["--preview"] = false,
      ["--preview-window"] = "hidden:right:0",
    },
    actions = actions,
  })
end

return M
