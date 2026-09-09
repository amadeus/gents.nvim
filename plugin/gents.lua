if vim.g.loaded_gents then
  return
end
vim.g.loaded_gents = true

-- Startup only registers entry points; modules load when a command or picker
-- first needs them. Picker highlights are defined when a menu first opens and
-- refreshed after colorscheme changes from then on.
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("GentsHighlights", { clear = true }),
  desc = "Refresh default Gents picker highlights",
  callback = function()
    if package.loaded["gents.picker"] then
      require("gents.picker").define_highlights()
    end
  end,
})

---@param opts gents.commands.Options
local function run(opts)
  require("gents.commands").run(opts)
end

vim.api.nvim_create_user_command("Gents", run, {
  nargs = "*",
  range = true,
  complete = function(...)
    return require("gents.commands").complete(...)
  end,
  desc = "Manage agent CLI sessions",
  force = true,
})
