local M = {}
local tools = require("agents.tools")

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

---@class agents.config.PendingTool: agents.ToolOverride
---@field name? string

---@class agents.config.PendingConfig: agents.Config
---@field tools table<string, agents.config.PendingTool>

---@param config agents.Config|agents.config.PendingConfig
local function validate(config)
  local layout_type = type(config.layout)
  if layout_type ~= "string" and layout_type ~= "table" and layout_type ~= "function" then
    error("agents: layout must be a string, float configuration table, or function", 3)
  end
  if config.on_exit ~= "keep" and config.on_exit ~= "close" then
    error('agents: on_exit must be "keep" or "close"', 3)
  end
  require("agents.keys").validate(config.keys)
  for name, tool in pairs(config.tools) do
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
        "agents: tools."
          .. name
          .. ".cmd must be a non-empty list of strings starting with an executable",
        3
      )
    end
  end
end

---@param opts? agents.SetupOptions
---@return agents.Config
function M.setup(opts)
  opts = vim.deepcopy(opts or {})
  local overrides = opts.tools or {}
  opts.tools = nil
  ---@type agents.Config|agents.config.PendingConfig
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for name, override in pairs(overrides) do
    if override == false then
      config.tools[name] = nil
    else
      assert(
        type(override) == "table",
        "agents: tools." .. name .. " must be a tool table or false"
      )
      ---@type agents.config.PendingTool
      local tool = vim.tbl_extend("force", config.tools[name] or {}, override)
      tool.name = name
      config.tools[name] = tool
    end
  end
  validate(config)
  ---@cast config agents.Config
  current = config
  return config
end

---@return agents.Config
function M.get()
  return current or M.setup()
end

return M
