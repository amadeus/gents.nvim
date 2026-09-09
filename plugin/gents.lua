if vim.g.loaded_gents then
  return
end
vim.g.loaded_gents = true

local highlights = require("gents.picker").define_highlights
highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("GentsHighlights", { clear = true }),
  desc = "Set default Gents picker highlights",
  callback = highlights,
})

require("gents.commands").setup()
