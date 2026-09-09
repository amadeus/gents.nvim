if vim.g.loaded_agents then
  return
end
vim.g.loaded_agents = true

local highlights = require("agents.picker").define_highlights
highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("AgentsHighlights", { clear = true }),
  desc = "Set default Agents picker highlights",
  callback = highlights,
})

require("agents.commands").setup()
