if vim.g.loaded_agents then
  return
end
vim.g.loaded_agents = true

require("agents.commands").setup()
