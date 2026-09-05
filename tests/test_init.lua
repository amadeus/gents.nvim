local test = require("mini.test")
local T = test.new_set()

T["plugin and module load"] = function()
  test.expect.equality(vim.g.loaded_agents, true)
  test.expect.equality(type(require("agents")), "table")
  test.expect.equality(vim.fn.exists(":Agents"), 2)
  require("agents").setup()
end

return T
