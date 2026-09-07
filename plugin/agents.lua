if vim.g.loaded_agents then
  return
end
vim.g.loaded_agents = true

---@return nil
local function highlights()
  local links = {
    AgentsPickerDirectory = "SnacksPickerDir",
    AgentsPickerVisible = "DiagnosticInfo",
    AgentsPickerHidden = "Comment",
    AgentsPickerPlaceholder = "Comment",
    AgentsPickerSeparator = "Comment",
    AgentsPickerDescription = "Comment",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("AgentsHighlights", { clear = true }),
  desc = "Set default Agents picker highlights",
  callback = highlights,
})

require("agents.commands").setup()
