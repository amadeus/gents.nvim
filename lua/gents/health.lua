local M = {}

---@return nil
function M.check()
  local config = require("gents.config").get()

  vim.health.start("Tools")
  local enabled = 0
  for _, name in ipairs(require("gents.tools").names(config.tools)) do
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
  elseif config.picker == "snacks" then
    if pcall(require, "snacks") then
      vim.health.ok("Using Snacks picker")
    else
      vim.health.error(
        "Snacks picker is configured but snacks.nvim is unavailable",
        "Install and configure folke/snacks.nvim, or set picker to nil to use vim.ui.select."
      )
    end
  elseif config.picker == "mini" then
    if require("gents.pickers.mini").instance() then
      vim.health.ok("Using mini.pick picker")
    else
      vim.health.error(
        "mini.pick picker is configured but mini.pick is not set up",
        'Install nvim-mini/mini.nvim or mini.pick and call require("mini.pick").setup(), or set picker to nil to use vim.ui.select.'
      )
    end
  elseif config.picker == "telescope" then
    if require("gents.pickers.telescope").instance() then
      vim.health.ok("Using Telescope picker")
    else
      vim.health.error(
        "Telescope picker is configured but telescope.nvim or plenary.nvim is unavailable",
        "Install nvim-telescope/telescope.nvim with nvim-lua/plenary.nvim, or set picker to nil to use vim.ui.select."
      )
    end
  elseif config.picker == "fzf-lua" then
    local fzf = require("gents.pickers.fzf")
    local modules = fzf.instance()
    local binary = modules and fzf.binary(modules)
    if not modules then
      vim.health.error(
        "fzf-lua picker is configured but fzf-lua is unavailable",
        "Install ibhagwan/fzf-lua and the fzf executable, or set picker to nil to use vim.ui.select."
      )
    elseif not binary then
      vim.health.error(
        "fzf-lua picker is configured but the fzf executable was not found ("
          .. (modules.fzf_bin or "fzf")
          .. ")",
        "Install fzf or set fzf_bin in fzf-lua's setup, or set picker to nil to use vim.ui.select."
      )
    else
      vim.health.ok("Using fzf-lua picker (" .. binary .. ")")
    end
  elseif type(config.picker) == "function" then
    vim.health.ok("Using a custom picker function")
  else
    vim.health.warn(
      'picker must be nil, "snacks", "mini", "telescope", "fzf-lua", or a function',
      "Set picker to nil to use vim.ui.select."
    )
  end
end

return M
