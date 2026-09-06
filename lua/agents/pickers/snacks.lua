local M = {}

---@type table<string, string>
local chunk_highlights = {
  directory = "SnacksPickerDir",
  visible = "DiagnosticInfo",
  hidden = "Comment",
  placeholder = "Comment",
  separator = "Comment",
  description = "Comment",
}

-- Only the Snacks surface used by this adapter is described here, so Snacks
-- remains optional and its type definitions are not required by LuaLS.
---@class agents.pickers.SnacksItem
---@field text string
---@field agents_index integer
---@field preview? { text: string }

---@class agents.pickers.SnacksPicker
---@field close fun(self: agents.pickers.SnacksPicker)

---@alias agents.pickers.SnacksAction fun(picker: agents.pickers.SnacksPicker, item?: agents.pickers.SnacksItem)
---@alias agents.pickers.SnacksKey { [1]: string, mode: string[], desc: string }
---@alias agents.pickers.SnacksHighlight { [1]: string, [2]?: string }
---@alias agents.pickers.SnacksBinding { [1]: string, [2]: string, [3]: string }
---@alias agents.pickers.SnacksBorderChar string|{ [1]: string, [2]?: string }
---@alias agents.pickers.SnacksBorder string|boolean|agents.pickers.SnacksBorderChar[]

---@class agents.pickers.SnacksWindowOptions
---@field keys table<string, agents.pickers.SnacksKey>
---@field border? agents.pickers.SnacksBorder
---@field footer? agents.pickers.SnacksHighlight[]
---@field footer_pos? "left"|"center"|"right"
---@field footer_keys? boolean

---@class agents.pickers.SnacksLayoutNode
---@field win? string
---@field border? agents.pickers.SnacksBorder
---@field [integer] agents.pickers.SnacksLayoutNode

---@class agents.pickers.SnacksLayout
---@field layout? agents.pickers.SnacksLayoutNode
---@field config? fun(layout: agents.pickers.SnacksLayout): agents.pickers.SnacksLayout?

---@alias agents.pickers.SnacksLayoutResolver fun(source?: string): agents.pickers.SnacksLayout|string

---@class agents.pickers.SnacksLayoutOptions
---@field layout? agents.pickers.SnacksLayout|string|agents.pickers.SnacksLayoutResolver
---@field layouts? table<string, agents.pickers.SnacksLayout>
---@field source? string

---@class agents.pickers.SnacksOptions: agents.pickers.SnacksLayoutOptions
---@field title string
---@field items agents.pickers.SnacksItem[]
---@field format fun(item: agents.pickers.SnacksItem): agents.pickers.SnacksHighlight[]
---@field preview string
---@field confirm string
---@field actions table<string, agents.pickers.SnacksAction>
---@field win { input: agents.pickers.SnacksWindowOptions, list: agents.pickers.SnacksWindowOptions }
---@field config? fun(opts: agents.pickers.SnacksOptions)

---@param border? agents.pickers.SnacksBorder
---@return agents.pickers.SnacksBorder
local function footer_border(border)
  if border == true and vim.o.winborder:find(",") then
    border = vim.split(vim.o.winborder, ",", { plain = true })
  end
  if not border or border == "" or border == "none" then
    return "bottom"
  end
  ---@type table<string, agents.pickers.SnacksBorderChar[]>
  local edges = {
    top = { "", "─", "", "", "", "─", "", "" },
    left = { "", "", "", "", "", "─", " ", "│" },
    right = { "", "", "", "│", " ", "─", "", "" },
    hpad = { "", "", "", " ", " ", "─", " ", " " },
  }
  if type(border) == "string" then
    return edges[border] or border
  elseif type(border) ~= "table" then
    return border
  elseif #border == 0 then
    return "bottom"
  end
  local bottom = border[5 % #border + 1]
  if bottom == "" or (type(bottom) == "table" and bottom[1] == "") then
    ---@type agents.pickers.SnacksBorderChar[]
    local expanded = {}
    for i = 1, 8 do
      expanded[i] = border[(i - 1) % #border + 1]
    end
    expanded[6] = "─"
    -- Neovim requires a corner where a side edge meets the new bottom edge.
    for _, side in ipairs({ 4, 8 }) do
      local edge, corner = expanded[side], expanded[side == 4 and 5 or 7]
      local edge_text = type(edge) == "table" and edge[1] or edge
      local corner_text = type(corner) == "table" and corner[1] or corner
      if edge_text ~= "" and corner_text == "" then
        if type(corner) == "table" then
          expanded[side == 4 and 5 or 7] = { " ", corner[2] }
        else
          expanded[side == 4 and 5 or 7] = " "
        end
      end
    end
    return expanded
  end
  return border
end

---@param node? agents.pickers.SnacksLayoutNode
---@param inherited? agents.pickers.SnacksBorder
local function list_border(node, inherited)
  if not node then
    return
  end
  local border = node.border == nil and inherited or node.border
  if node.win == "list" then
    node.border = footer_border(border)
  end
  for _, child in ipairs(node) do
    list_border(child, inherited)
  end
end

---@generic T
---@param spec agents.PickerSpec<T>
function M.open(spec)
  ---@type boolean, { picker: fun(opts: agents.pickers.SnacksOptions) }
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify(
      'agents.nvim: picker = "snacks" requires snacks.nvim; install and configure Snacks with picker.enabled = true',
      vim.log.levels.ERROR
    )
    return
  end

  ---@type agents.pickers.SnacksItem[]
  local items = {}
  ---@type table<string, agents.pickers.SnacksAction>
  local actions = {}
  ---@type table<string, agents.pickers.SnacksKey>
  local keys = {}
  ---@type table<string, string>
  local labels = { new = "start", show = "show", run = "run", send = "send" }
  ---@type agents.pickers.SnacksBinding[]
  local bindings = {
    { spec.default, "<CR>", labels[spec.default] or spec.default },
    { "vsplit", "<C-v>", "vsplit" },
    { "split", "<C-x>", "split" },
    { "tabnew", "<C-t>", "tab" },
    { "current", "<C-CR>", "here" },
    { "edit_args", "<C-e>", "args" },
    { "hide", "<C-h>", "hide" },
    { "close", "<C-d>", "close" },
  }
  for index, item in ipairs(spec.items) do
    items[index] = {
      text = item.text,
      agents_index = index,
      preview = item.preview and { text = item.preview } or nil,
    }
  end
  for name, action in pairs(spec.actions) do
    local id = "agents_" .. name
    actions[id] = function(picker, item)
      if not item then
        return
      end
      picker:close()
      vim.schedule(function()
        action(spec.items[item.agents_index])
      end)
    end
  end
  ---@type agents.pickers.SnacksHighlight[]
  local footer = {}
  local help = require("agents.config").get().picker_help
  for _, binding in ipairs(bindings) do
    local name, key, label = binding[1], binding[2], binding[3]
    if spec.actions[name] then
      keys[key] = { "agents_" .. name, mode = { "n", "i" }, desc = label }
      if help and key ~= "<CR>" then
        if #footer > 0 then
          footer[#footer + 1] = { " ", "SnacksFooter" }
        end
        footer[#footer + 1] = { " " .. key:sub(2, -2):gsub("CR", "Ent") .. " ", "SnacksFooterKey" }
        footer[#footer + 1] = { " " .. label .. " ", "SnacksFooterDesc" }
      end
    end
  end
  if #footer > 0 then
    table.insert(footer, 1, { " ", "SnacksFooter" })
    footer[#footer + 1] = { " ", "SnacksFooter" }
  end
  snacks.picker({
    title = spec.title,
    items = items,
    format = function(item)
      local source = spec.items[item.agents_index]
      if not source.chunks then
        return { { item.text, source.hl } }
      end
      ---@type agents.pickers.SnacksHighlight[]
      local chunks = {}
      for _, chunk in ipairs(source.chunks) do
        chunks[#chunks + 1] = {
          chunk.text,
          chunk.kind and chunk_highlights[chunk.kind] or source.hl,
        }
      end
      return chunks
    end,
    preview = "preview",
    confirm = "agents_" .. spec.default,
    actions = actions,
    config = function(opts)
      ---@type agents.pickers.SnacksLayoutOptions
      local original = { layout = opts.layout, layouts = opts.layouts, source = opts.source }
      opts.layout = function()
        ---@type { layout: fun(opts: agents.pickers.SnacksLayoutOptions): agents.pickers.SnacksLayout }
        local config = require("snacks.picker.config")
        local layout = vim.deepcopy(config.layout(original))
        if #footer > 0 then
          list_border(layout.layout, opts.win.list.border)
        end
        -- The original layout callback has already run during resolution.
        layout.config = nil
        return layout
      end
    end,
    win = {
      input = { keys = keys },
      list = {
        keys = keys,
        footer = #footer > 0 and footer or nil,
        footer_pos = "center",
        footer_keys = false,
      },
    },
  })
end

return M
