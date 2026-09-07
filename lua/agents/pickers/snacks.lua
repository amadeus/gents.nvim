local M = {}

---@type table<string, string>
local chunk_highlights = {
  directory = "AgentsPickerDirectory",
  visible = "AgentsPickerVisible",
  hidden = "AgentsPickerHidden",
  placeholder = "AgentsPickerPlaceholder",
  separator = "AgentsPickerSeparator",
  description = "AgentsPickerDescription",
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
---@field min_width? number
---@field max_width? number
---@field footer? agents.pickers.SnacksHighlight[]
---@field footer_pos? "left"|"center"|"right"
---@field footer_keys? boolean

---@class agents.pickers.SnacksLayoutNode
---@field win? string
---@field border? agents.pickers.SnacksBorder
---@field box? "horizontal"|"vertical"
---@field width? number|fun(win: agents.pickers.SnacksMeasure): number?
---@field min_width? number
---@field max_width? number
---@field position? string
---@field [integer] agents.pickers.SnacksLayoutNode

---@class agents.pickers.SnacksMeasure
---@field opts agents.pickers.SnacksLayoutNode
---@field dim fun(self: agents.pickers.SnacksMeasure, parent: { width: number, height: number }): { width: number, height: number }
---@field border_size fun(self: agents.pickers.SnacksMeasure): { left: number, right: number }
---@field parent_size fun(self: agents.pickers.SnacksMeasure): { width: number, height: number }

---@class agents.pickers.SnacksLayout
---@field layout? agents.pickers.SnacksLayoutNode
---@field hidden? string[]
---@field preview? string
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

---@param layout agents.pickers.SnacksLayout
---@param cells integer
---@param defaults table<string, agents.pickers.SnacksWindowOptions>
local function help_width(layout, cells, defaults)
  local root = layout.layout
  if not root then
    return
  end
  ---@type agents.pickers.SnacksMeasure
  local native = require("snacks.win")
  local available = vim.o.columns
  ---@type table<agents.pickers.SnacksLayoutNode, agents.pickers.SnacksMeasure>
  local windows = {}
  ---@type table<agents.pickers.SnacksLayoutNode, number>
  local minimums = {}

  ---@param node agents.pickers.SnacksLayoutNode
  ---@return agents.pickers.SnacksMeasure
  local function measure(node)
    if not windows[node] then
      local opts = vim.deepcopy(node)
      local inherited = node.win and defaults[node.win] or nil
      if inherited then
        opts.min_width = opts.min_width or inherited.min_width
        opts.max_width = opts.max_width or inherited.max_width
        if opts.border == nil then
          opts.border = inherited.border
        end
      end
      -- Snacks uses the same options-only measurement for its layout boxes.
      local win = setmetatable({ opts = opts }, native)
      ---@cast win agents.pickers.SnacksMeasure
      windows[node] = win
    end
    return windows[node]
  end

  ---@param node agents.pickers.SnacksLayoutNode
  ---@return boolean
  local function included(node)
    return not node.win
      or not (
        vim.list_contains(layout.hidden or {}, node.win)
        or (node.win == "preview" and layout.preview == "main")
      )
  end

  ---@param node agents.pickers.SnacksLayoutNode
  ---@return number? Required outer width, only for the path containing the list.
  local function required(node)
    if not included(node) then
      return
    end
    ---@type number?
    local needed = node.win == "list" and cells or nil
    ---@type agents.pickers.SnacksLayoutNode?
    local target
    for _, child in ipairs(node) do
      local width = required(child)
      if width then
        target, needed = child, width
      end
    end
    if not needed then
      return
    end
    if target and node.box == "horizontal" then
      local width = needed
      while width <= available do
        local fixed, flex, share = 0, 0, 1
        for _, child in ipairs(node) do
          if included(child) then
            local win = measure(child)
            local option = win.opts.width
            local size = 0
            if type(option) == "function" then
              size = option(win) or 0
            elseif type(option) == "number" then
              size = option
            end
            local border = win:border_size()
            local edges = border.left + border.right
            if size > 0 then
              fixed = fixed + win:dim({ width = width, height = vim.o.lines }).width + edges
            else
              flex = flex + 1
              share =
                math.max(share, child == target and needed or (win.opts.min_width or 1) + edges)
            end
          end
        end
        local next_width = math.ceil(fixed + flex * share)
        if next_width <= width then
          break
        end
        width = next_width
      end
      needed = width
    end
    local win = measure(node)
    needed = math.max(needed, win.opts.min_width or 0)
    minimums[node] = needed
    win.opts.min_width = needed
    if win.opts.max_width then
      win.opts.max_width = math.max(win.opts.max_width, needed)
    end
    local border = win:border_size()
    return needed + border.left + border.right
  end

  local total = required(root)
  if not total then
    return
  end
  -- Oversized descendant minima can overflow their allocated share after borders.
  -- On small screens enlarge only the root and let Snacks clip the footer.
  if total <= available then
    for node, minimum in pairs(minimums) do
      node.min_width = minimum
      node.max_width = measure(node).opts.max_width
    end
  end
  local border = measure(root):border_size()
  local limit = math.max(1, available - border.left - border.right)
  root.min_width = math.min(limit, math.max(root.min_width or 0, assert(minimums[root])))
  root.max_width = math.min(limit, math.max(root.max_width or limit, root.min_width))
  if root.position and root.position ~= "float" then
    -- Snacks wraps split roots and carries width, but not their minimum/maximum.
    local original = root.width
    root.width = function(win)
      local width = 0
      if type(original) == "function" then
        width = original(win) or 0
      elseif type(original) == "number" then
        width = original
      end
      local parent = win:parent_size().width
      width = width == 0 and parent or (width < 1 and math.floor(parent * width) or width)
      return math.min(parent, math.max(width, total))
    end
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
    { "float", "<C-f>", "float" },
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
  ---@type string[]
  local hints = {}
  for _, chunk in ipairs(footer) do
    hints[#hints + 1] = chunk[1]
  end
  local footer_width = vim.fn.strdisplaywidth(table.concat(hints)) + 2
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
          help_width(layout, footer_width, opts.win)
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
