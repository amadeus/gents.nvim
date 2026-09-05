local M = {}

---@return nil
function M.check()
  local config = require("agents.config").get()

  vim.health.start("Tools")
  local enabled = 0
  for _, name in ipairs(require("agents.tools").names(config.tools)) do
    local tool = config.tools[name]
    if tool.enabled ~= false then
      enabled = enabled + 1
      local executable = tool.cmd[1]
      if vim.fn.executable(executable) == 1 then
        vim.health.ok(name .. ": executable found (" .. executable .. ")")
      else
        local advice = tool.url and ("Install: " .. tool.url)
          or ("Install " .. executable .. " and ensure it is executable in $PATH.")
        vim.health.warn(name .. ": executable not found (" .. executable .. ")", advice)
      end
    end
  end
  if enabled == 0 then
    vim.health.info("No tools are enabled.")
  end

  vim.health.start("Editor")
  if vim.o.autoread then
    vim.health.ok("autoread is enabled")
  else
    vim.health.warn(
      "autoread is disabled; files changed by agents may not reload automatically.",
      "Enable it with :set autoread or vim.opt.autoread = true."
    )
  end

  vim.health.start("Picker")
  if config.picker == nil then
    vim.health.ok("Using vim.ui.select")
  elseif type(config.picker) == "function" then
    vim.health.ok("Using a custom picker function")
  else
    vim.health.warn("picker must be nil or a function", "Set picker to nil to use vim.ui.select.")
  end
end

return M
