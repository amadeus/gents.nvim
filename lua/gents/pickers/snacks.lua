local M = {}

-- Only the Snacks surface used by this adapter is described here, so Snacks
-- remains optional and its type definitions are not required by LuaLS.
---@class gents.pickers.SnacksItem
---@field text string
---@field gents_index integer
---@field preview? { text: string }

---@class gents.pickers.SnacksPicker
---@field close fun(self: gents.pickers.SnacksPicker)

---@alias gents.pickers.SnacksAction fun(picker: gents.pickers.SnacksPicker, item?: gents.pickers.SnacksItem)
---@alias gents.pickers.SnacksKey { [1]: string, mode: string[], desc: string }
---@alias gents.pickers.SnacksHighlight { [1]: string, [2]?: string }
---@alias gents.pickers.SnacksBinding { [1]: string, [2]: string, [3]: string }
---@alias gents.pickers.SnacksBorderChar string|{ [1]: string, [2]?: string }
---@alias gents.pickers.SnacksBorder string|boolean|gents.pickers.SnacksBorderChar[]

---@class gents.pickers.SnacksWindowOptions
---@field keys table<string, gents.pickers.SnacksKey>
---@field border? gents.pickers.SnacksBorder
---@field min_width? number
---@field max_width? number
---@field footer? gents.pickers.SnacksHighlight[]
---@field footer_pos? "left"|"center"|"right"
---@field footer_keys? boolean

---@class gents.pickers.SnacksLayoutNode
---@field win? string
---@field border? gents.pickers.SnacksBorder
---@field box? "horizontal"|"vertical"
---@field width? number|fun(win: gents.pickers.SnacksMeasure): number?
---@field min_width? number
---@field max_width? number
---@field position? string
---@field [integer] gents.pickers.SnacksLayoutNode

---@class gents.pickers.SnacksMeasure
---@field opts gents.pickers.SnacksLayoutNode
---@field dim fun(self: gents.pickers.SnacksMeasure, parent: { width: number, height: number }): { width: number, height: number }
---@field border_size fun(self: gents.pickers.SnacksMeasure): { left: number, right: number }
---@field parent_size fun(self: gents.pickers.SnacksMeasure): { width: number, height: number }

---@class gents.pickers.SnacksLayout
---@field layout? gents.pickers.SnacksLayoutNode
---@field hidden? string[]
---@field preview? string
---@field config? fun(layout: gents.pickers.SnacksLayout): gents.pickers.SnacksLayout?

---@alias gents.pickers.SnacksLayoutResolver fun(source?: string): gents.pickers.SnacksLayout|string

---@class gents.pickers.SnacksLayoutOptions
---@field layout? gents.pickers.SnacksLayout|string|gents.pickers.SnacksLayoutResolver
---@field layouts? table<string, gents.pickers.SnacksLayout>
---@field source? string

---@class gents.pickers.SnacksOptions: gents.pickers.SnacksLayoutOptions
---@field title string
---@field items gents.pickers.SnacksItem[]
---@field format fun(item: gents.pickers.SnacksItem): gents.pickers.SnacksHighlight[]
---@field preview string
---@field confirm string
---@field actions table<string, gents.pickers.SnacksAction>
---@field win { input: gents.pickers.SnacksWindowOptions, list: gents.pickers.SnacksWindowOptions }
---@field config? fun(opts: gents.pickers.SnacksOptions)

---@param border? gents.pickers.SnacksBorder
---@return gents.pickers.SnacksBorder
local function footer_border(border)
  if border == true and vim.o.winborder:find(",") then
    border = vim.split(vim.o.winborder, ",", { plain = true })
  end
  if not border or border == "" or border == "none" then
    return "bottom"
  end
  ---@type table<string, gents.pickers.SnacksBorderChar[]>
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
    ---@type gents.pickers.SnacksBorderChar[]
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

---@param node? gents.pickers.SnacksLayoutNode
---@param inherited? gents.pickers.SnacksBorder
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

---@param layout gents.pickers.SnacksLayout
---@param cells integer
---@param defaults table<string, gents.pickers.SnacksWindowOptions>
local function help_width(layout, cells, defaults)
  local root = layout.layout
  if not root then
    return
  end
  ---@type gents.pickers.SnacksMeasure
  local native = require("snacks.win")
  local available = vim.o.columns
  ---@type table<gents.pickers.SnacksLayoutNode, gents.pickers.SnacksMeasure>
  local windows = {}
  ---@type table<gents.pickers.SnacksLayoutNode, number>
  local minimums = {}

  ---@param node gents.pickers.SnacksLayoutNode
  ---@return gents.pickers.SnacksMeasure
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
      ---@cast win gents.pickers.SnacksMeasure
      windows[node] = win
    end
    return windows[node]
  end

  ---@param node gents.pickers.SnacksLayoutNode
  ---@return boolean
  local function included(node)
    return not node.win
      or not (
        vim.list_contains(layout.hidden or {}, node.win)
        or (node.win == "preview" and layout.preview == "main")
      )
  end

  ---@param node gents.pickers.SnacksLayoutNode
  ---@return number? Required outer width, only for the path containing the list.
  local function required(node)
    if not included(node) then
      return
    end
    ---@type number?
    local needed = node.win == "list" and cells or nil
    ---@type gents.pickers.SnacksLayoutNode?
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
---@param spec gents.PickerSpec<T>
function M.open(spec)
  ---@type boolean, { picker: fun(opts: gents.pickers.SnacksOptions) }
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify(
      'gents.nvim: picker = "snacks" requires snacks.nvim; install and configure Snacks with picker.enabled = true',
      vim.log.levels.ERROR
    )
    return
  end

  ---@type gents.pickers.SnacksItem[]
  local items = {}
  ---@type table<string, gents.pickers.SnacksAction>
  local actions = {}
  ---@type table<string, gents.pickers.SnacksKey>
  local keys = {}
  ---@type table<string, string>
  local labels = { new = "start", show = "show", run = "run", send = "send" }
  ---@type gents.pickers.SnacksBinding[]
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
      gents_index = index,
      preview = item.preview and { text = item.preview } or nil,
    }
  end
  for name, action in pairs(spec.actions) do
    local id = "gents_" .. name
    actions[id] = function(picker, item)
      if not item then
        return
      end
      picker:close()
      vim.schedule(function()
        action(spec.items[item.gents_index])
      end)
    end
  end
  ---@type gents.pickers.SnacksHighlight[]
  local footer = {}
  local help = require("gents.config").get().picker_help
  for _, binding in ipairs(bindings) do
    local name, key, label = binding[1], binding[2], binding[3]
    if spec.actions[name] then
      keys[key] = { "gents_" .. name, mode = { "n", "i" }, desc = label }
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
      local source = spec.items[item.gents_index]
      if not source.chunks then
        return { { item.text, source.hl } }
      end
      ---@type gents.pickers.SnacksHighlight[]
      local chunks = {}
      for _, chunk in ipairs(source.chunks) do
        chunks[#chunks + 1] = {
          chunk.text,
          chunk.kind and require("gents.picker").chunk_highlights[chunk.kind] or source.hl,
        }
      end
      return chunks
    end,
    preview = "preview",
    confirm = "gents_" .. spec.default,
    actions = actions,
    config = function(opts)
      ---@type gents.pickers.SnacksLayoutOptions
      local original = { layout = opts.layout, layouts = opts.layouts, source = opts.source }
      opts.layout = function()
        ---@type { layout: fun(opts: gents.pickers.SnacksLayoutOptions): gents.pickers.SnacksLayout }
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
