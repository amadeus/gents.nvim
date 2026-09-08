local test = require("mini.test")
local T = test.new_set()

T["plugin and module load"] = function()
  test.expect.equality(vim.g.loaded_agents, true)
  test.expect.equality(type(require("agents")), "table")
  test.expect.equality(vim.fn.exists(":Agents"), 2)
  require("agents").setup()
end

---@return string
local function directory_link()
  return vim.fn.hlexists("SnacksPickerDir") == 1 and "SnacksPickerDir" or "NonText"
end

T["picker highlight defaults preserve overrides on colorscheme changes"] = function()
  local links = {
    AgentsPickerDirectory = "AgentsPickerDirectoryDefault",
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
  -- Snacks defines its groups after this plugin loads; a refresh follows them.
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "default", modeline = false })
  for name, link in pairs(links) do
    test.expect.equality(vim.api.nvim_get_hl(0, { name = name }).link, link)
  end
  local default = vim.api.nvim_get_hl(0, { name = "AgentsPickerDirectoryDefault" })
  test.expect.equality(default.link, directory_link())
  vim.cmd.colorscheme("default")
  for name, link in pairs(links) do
    test.expect.equality(vim.api.nvim_get_hl(0, { name = name }).link, link)
  end
  default = vim.api.nvim_get_hl(0, { name = "AgentsPickerDirectoryDefault" })
  test.expect.equality(default.link, directory_link())

  vim.api.nvim_set_hl(0, "AgentsPickerVisible", { fg = 0x123456, bold = true })
  local custom = vim.api.nvim_get_hl(0, { name = "AgentsPickerVisible" })
  vim.api.nvim_set_hl(0, "AgentsPickerSeparator", {})
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerSeparator" }).link, nil)
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "default", modeline = false })
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerVisible" }), custom)
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerSeparator" }), {})
end

T["directory highlight follows Snacks styling once its group exists"] = function()
  local define = require("agents.picker").define_highlights
  test.finally(function()
    vim.api.nvim_set_hl(
      0,
      "AgentsPickerDirectory",
      { default = true, force = true, link = "AgentsPickerDirectoryDefault" }
    )
    define()
  end)
  if vim.fn.hlexists("SnacksPickerDir") == 0 then
    vim.api.nvim_set_hl(0, "SnacksPickerDir", { link = "Directory" })
  end
  -- The plugin-owned default defined before Snacks was available follows it
  -- afterwards, while a user's own definitions are kept, even a NonText link.
  vim.api.nvim_set_hl(0, "AgentsPickerDirectoryDefault", { link = "NonText" })
  vim.api.nvim_set_hl(0, "AgentsPickerDirectory", { link = "NonText" })
  define()
  test.expect.equality(
    vim.api.nvim_get_hl(0, { name = "AgentsPickerDirectoryDefault" }).link,
    "SnacksPickerDir"
  )
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "AgentsPickerDirectory" }).link, "NonText")
  vim.api.nvim_set_hl(0, "AgentsPickerDirectory", { fg = 0x123456 })
  define()
  test.expect.equality(
    vim.api.nvim_get_hl(0, { name = "AgentsPickerDirectory" }),
    { fg = 0x123456 }
  )
end

return T
