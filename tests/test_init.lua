local test = require("mini.test")
local T = test.new_set()

T["plugin and module load"] = function()
  test.expect.equality(vim.g.loaded_agents, true)
  test.expect.equality(type(require("agents")), "table")
  test.expect.equality(vim.fn.exists(":Agents"), 2)
  require("agents").setup()
end

T["picker highlight defaults preserve overrides on colorscheme changes"] = function()
  local links = {
    AgentsPickerDirectory = "SnacksPickerDir",
    AgentsPickerVisible = "DiagnosticInfo",
    AgentsPickerHidden = "Comment",
    AgentsPickerPlaceholder = "Comment",
    AgentsPickerSeparator = "Comment",
    AgentsPickerDescription = "Comment",
  }
  test.finally(function()
    for name, link in pairs(links) do
      vim.api.nvim_set_hl(0, name, { default = true, force = true, link = link })
    end
  end)
  for name, link in pairs(links) do
    test.expect.equality(vim.api.nvim_get_hl(0, { name = name }).link, link)
  end
  vim.cmd.colorscheme("default")
  for name, link in pairs(links) do
    test.expect.equality(vim.api.nvim_get_hl(0, { name = name }).link, link)
  end

  vim.api.nvim_set_hl(0, "AgentsPickerVisible", { fg = 0x123456, bold = true })
  local custom = vim.api.nvim_get_hl(0, { name = "AgentsPickerVisible" })
  vim.api.nvim_set_hl(0, "AgentsPickerSeparator", {})
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerSeparator" }).link, nil)
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "default", modeline = false })
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerVisible" }), custom)
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerSeparator" }), {})
end

return T
