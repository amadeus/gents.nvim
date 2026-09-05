local M = {}
local tools = require("agents.tools")

---@class agents.Config
---@field layout string|table|fun(buf: integer): integer
---@field float table
---@field picker? fun(spec: agents.PickerSpec)
---@field on_exit "keep"|"close"
---@field tools table<string, agents.Tool>
---@field prompts table
---@field keys table[]

---@type agents.Config
local defaults = {
  layout = "vsplit",
  float = { width = 0.8, height = 0.8, border = "rounded" },
  picker = nil,
  on_exit = "keep",
  tools = tools.defaults,
  prompts = {},
  keys = {},
}

---@type agents.Config?
local current

---@param config agents.Config
local function validate(config)
  local layout_type = type(config.layout)
  if layout_type ~= "string" and layout_type ~= "table" and layout_type ~= "function" then
    error("agents: layout must be a string, float configuration table, or function", 3)
  end
  if config.on_exit ~= "keep" and config.on_exit ~= "close" then
    error('agents: on_exit must be "keep" or "close"', 3)
  end
  for name, tool in pairs(config.tools) do
    local cmd = tool.cmd
    local valid = type(cmd) == "table" and vim.islist(cmd) and #cmd > 0 and cmd[1] ~= ""
    if valid then
      for _, arg in ipairs(cmd) do
        if type(arg) ~= "string" then
          valid = false
          break
        end
      end
    end
    if not valid then
      error(
        "agents: tools."
          .. name
          .. ".cmd must be a non-empty list of strings starting with an executable",
        3
      )
    end
  end
end

---@param opts? table
---@return agents.Config
function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  local overrides = opts.tools or {}
  opts.tools = nil
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for name, override in pairs(overrides) do
    if override == false then
      config.tools[name] = nil
    else
      assert(
        type(override) == "table",
        "agents: tools." .. name .. " must be a tool table or false"
      )
      local tool = config.tools[name] or {}
      for field, value in pairs(override) do
        tool[field] = value
      end
      tool.name = name
      config.tools[name] = tool
    end
  end
  validate(config)
  current = config
  return config
end

---@return agents.Config
function M.get()
  return current or M.setup()
end

return M
