local test = require("mini.test")
local T = test.new_set()

T["plugin and module load"] = function()
  test.expect.equality(vim.g.loaded_gents, true)
  test.expect.equality(type(require("gents")), "table")
  test.expect.equality(vim.fn.exists(":Gents"), 2)
  test.expect.equality(vim.fn.exists(":Agents"), 0)
  test.expect.equality(vim.g.loaded_agents, nil)
  require("gents").setup()
end

---Run Lua in a fresh Neovim after sourcing the plugin file.
---@param script string
---@return vim.SystemCompleted
local function child(script)
  local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
  return vim
    .system({
      vim.v.progpath,
      "--headless",
      "--clean",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "--cmd",
      "set runtimepath^=" .. vim.fn.fnameescape(root),
      "-c",
      "runtime plugin/gents.lua",
      "-c",
      "lua " .. script,
      "-c",
      "qa!",
    }, { text = true })
    :wait()
end

T["startup loads only the configuration modules"] = function()
  local result = child(table.concat({
    "require('gents').setup({ layout = 'split' })",
    "local loaded = vim.tbl_filter(function(name) return vim.startswith(name, 'gents') end, vim.tbl_keys(package.loaded))",
    "table.sort(loaded)",
    "io.stdout:write(table.concat(loaded, ' '))",
  }, "; "))
  test.expect.equality(result.code, 0)
  test.expect.equality(result.stdout, "gents gents.config gents.tools")
end

T["custom adapters see the picker highlight groups"] = function()
  local result = child(table.concat({
    "require('gents').setup({ picker = function(spec) io.stdout:write(spec.title .. ':' .. vim.fn.hlexists('GentsPickerVisible')) end })",
    "require('gents.picker').open({ title = 'Menu', items = {}, actions = {}, default = 'select' })",
  }, "; "))
  test.expect.equality(result.code, 0)
  test.expect.equality(result.stdout, "Menu:1")
end

---@return string
local function directory_link()
  return vim.fn.hlexists("SnacksPickerDir") == 1 and "SnacksPickerDir" or "NonText"
end

T["picker highlight defaults preserve overrides on colorscheme changes"] = function()
  local links = {
    GentsPickerDirectory = "GentsPickerDirectoryDefault",
    GentsPickerVisible = "DiagnosticInfo",
    GentsPickerHidden = "Comment",
    GentsPickerPlaceholder = "Comment",
    GentsPickerSeparator = "Comment",
    GentsPickerDescription = "Comment",
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
  local default = vim.api.nvim_get_hl(0, { name = "GentsPickerDirectoryDefault" })
  test.expect.equality(default.link, directory_link())
  vim.cmd.colorscheme("default")
  for name, link in pairs(links) do
    test.expect.equality(vim.api.nvim_get_hl(0, { name = name }).link, link)
  end
  default = vim.api.nvim_get_hl(0, { name = "GentsPickerDirectoryDefault" })
  test.expect.equality(default.link, directory_link())

  vim.api.nvim_set_hl(0, "GentsPickerVisible", { fg = 0x123456, bold = true })
  local custom = vim.api.nvim_get_hl(0, { name = "GentsPickerVisible" })
  vim.api.nvim_set_hl(0, "GentsPickerSeparator", {})
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "GentsPickerSeparator" }).link, nil)
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "default", modeline = false })
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "GentsPickerVisible" }), custom)
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "GentsPickerSeparator" }), {})
end

T["directory highlight follows Snacks styling once its group exists"] = function()
  local define = require("gents.picker").define_highlights
  test.finally(function()
    vim.api.nvim_set_hl(
      0,
      "GentsPickerDirectory",
      { default = true, force = true, link = "GentsPickerDirectoryDefault" }
    )
    define()
  end)
  if vim.fn.hlexists("SnacksPickerDir") == 0 then
    vim.api.nvim_set_hl(0, "SnacksPickerDir", { link = "Directory" })
  end
  -- The plugin-owned default defined before Snacks was available follows it
  -- afterwards, while a user's own definitions are kept, even a NonText link.
  vim.api.nvim_set_hl(0, "GentsPickerDirectoryDefault", { link = "NonText" })
  vim.api.nvim_set_hl(0, "GentsPickerDirectory", { link = "NonText" })
  define()
  test.expect.equality(
    vim.api.nvim_get_hl(0, { name = "GentsPickerDirectoryDefault" }).link,
    "SnacksPickerDir"
  )
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "GentsPickerDirectory" }).link, "NonText")
  vim.api.nvim_set_hl(0, "GentsPickerDirectory", { fg = 0x123456 })
  define()
  test.expect.equality(vim.api.nvim_get_hl(0, { name = "GentsPickerDirectory" }), { fg = 0x123456 })
end

return T
