local M = {}
local tools = require("gents.tools")

---@type gents.Config
local defaults = {
  layout = "botright vsplit",
  float = { width = 0.8, height = 0.8, border = "rounded" },
  buflisted = false,
  picker = nil,
  picker_help = true,
  icons = { visible = "●", hidden = "○" },
  on_exit = "keep",
  tools = tools.defaults,
  prompts = {},
  keys = {},
}

---@type gents.Config?
local current

---@class gents.config.PendingTool: gents.ToolOverride
---@field name? string

---@class gents.config.PendingConfig: gents.Config
---@field tools table<string, gents.config.PendingTool>

---@param config gents.Config|gents.config.PendingConfig
local function validate(config)
  local layout_type = type(config.layout)
  if layout_type ~= "string" and layout_type ~= "table" and layout_type ~= "function" then
    error("gents: layout must be a string, float configuration table, or function", 3)
  end
  if config.on_exit ~= "keep" and config.on_exit ~= "close" then
    error('gents: on_exit must be "keep" or "close"', 3)
  end
  assert(
    config.picker == nil
      or config.picker == "snacks"
      or config.picker == "mini"
      or config.picker == "telescope"
      or config.picker == "fzf-lua"
      or type(config.picker) == "function",
    'gents: picker must be nil, "snacks", "mini", "telescope", "fzf-lua", or a function'
  )
  assert(type(config.picker_help) == "boolean", "gents: picker_help must be a boolean")
  assert(type(config.buflisted) == "boolean", "gents: buflisted must be a boolean")
  assert(type(config.icons) == "table", "gents: icons must be a table")
  for name, icon in pairs({ visible = config.icons.visible, hidden = config.icons.hidden }) do
    assert(
      type(icon) == "string" and icon ~= "" and not icon:find("[%s%c]"),
      "gents: icons."
        .. name
        .. " must be a non-empty string without whitespace or control characters"
    )
  end
  require("gents.keys").validate(config.keys)
  assert(type(config.prompts) == "table", "gents: prompts must be a table of item lists")
  for name, items in pairs(config.prompts) do
    assert(
      type(name) == "string" and name ~= "" and not name:find("%s"),
      "gents: prompt names must be non-empty and contain no whitespace"
    )
    assert(
      type(items) == "table" and vim.islist(items) and #items > 0,
      "gents: prompts." .. name .. " must be a non-empty item list"
    )
  end
  for name, tool in pairs(config.tools) do
    assert(
      tool.title == nil or tool.title == false or type(tool.title) == "function",
      "gents: tools." .. name .. ".title must be a function or false"
    )
    assert(
      tool.location == nil or type(tool.location) == "function",
      "gents: tools." .. name .. ".location must be a function"
    )
    local cmd = tool.cmd
    local valid = false
    if type(cmd) == "table" and vim.islist(cmd) and #cmd > 0 and cmd[1] ~= "" then
      valid = true
      for _, arg in ipairs(cmd) do
        if type(arg) ~= "string" then
          valid = false
          break
        end
      end
    end
    if not valid then
      error(
        "gents: tools."
          .. name
          .. ".cmd must be a non-empty list of strings starting with an executable",
        3
      )
    end
  end
end

---@param opts? gents.SetupOptions
---@return gents.Config
function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  local overrides = opts.tools or {}
  opts.tools = nil
  ---@type gents.Config|gents.config.PendingConfig
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for name, override in pairs(overrides) do
    if override == false then
      config.tools[name] = nil
    else
      assert(type(override) == "table", "gents: tools." .. name .. " must be a tool table or false")
      ---@type gents.config.PendingTool
      local tool = vim.tbl_extend("force", config.tools[name] or {}, override)
      tool.name = name
      config.tools[name] = tool
    end
  end
  validate(config)
  ---@cast config gents.Config
  current = config
  return config
end

---@return gents.Config
function M.get()
  return current or M.setup()
end

return M
