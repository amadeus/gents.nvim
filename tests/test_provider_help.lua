local test = require("mini.test")
local H = require("tests.helpers")
local context = require("agents.context")
local render = require("agents.providers.help")
local eq = test.expect.equality

local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

---@param lines string[]
---@param row? integer
---@param column? integer
---@return agents.Context
local function help_buffer(lines, row, column)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "help"
  vim.api.nvim_win_set_cursor(0, { row or 1, column or 0 })
  return context.capture()
end

T["help applies only to help buffers"] = function()
  eq(render(context.capture()), nil)
  vim.bo.filetype = "lua"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "*not-help*" })
  eq(render(context.capture()), nil)
  eq(render(help_buffer({ "", "" })), nil)
end

T["tag under cursor wins over aliases and uses its surrounding section"] = function()
  local header = "A topic *first-tag* *second-tag*"
  local column = assert(header:find("second-tag", 1, true)) - 1
  local ctx =
    help_buffer({ "Previous *previous*", "", header, "Body.", "", "Next *next*" }, 3, column)
  eq(render(ctx), {
    { text = "Help: :help second-tag" },
    { code = header .. "\nBody.", ft = "help" },
  })
end

T["references use captured cursor and buffer after focus changes"] = function()
  local ctx =
    help_buffer({ "Topic *topic*", "See |other-topic| for details.", "===", "Next." }, 2, 8)
  vim.cmd.new()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unrelated current buffer" })
  eq(render(ctx), {
    { text = "Help: :help other-topic" },
    { code = "Topic *topic*\nSee |other-topic| for details.", ft = "help" },
  })
end

T["section text retains code examples and contiguous tagged table rows"] = function()
  local lines = {
    "Topic *topic*",
    "",
    "An example: >vim",
    "  *example-tag*",
    "  echo 'keep indentation'",
    "<",
    "Key table ~",
    "A    *key-a*",
    "B    *key-b*",
    "",
    "-----",
    "Another section.",
  }
  eq(render(help_buffer(lines, 3)), {
    { text = "Help: :help topic" },
    { code = table.concat(lines, "\n", 1, 9), ft = "help" },
  })
end

T["untagged help sections still provide their text"] = function()
  eq(render(help_buffer({ "Introduction.", "Read this." }, 2)), {
    { code = "Introduction.\nRead this.", ft = "help" },
  })
end

T["real Neovim help includes the selected tag and section without the next topic"] = function()
  vim.cmd.help("help-writing")
  eq(vim.bo.filetype, "help")
  local ctx = context.capture()
  local parts = assert(render(ctx))
  eq(parts[1], { text = "Help: :help help-writing" })
  local output = require("agents.render").text(parts, ctx)
  eq(output:find("Writing help files", 1, true) ~= nil, true)
  eq(output:find("*plugin_name.txt*", 1, true) ~= nil, true)
  eq(output:find("*help-codeblock*", 1, true), nil)
end

return T
