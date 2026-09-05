local test = require("mini.test")
local T = test.new_set()
if not vim.env.SNACKS_DIR then
  return T
end

-- The optional integration uses this small surface of the real Snacks API.
---@class agents.test.SnacksWindow
---@field win { win?: integer }

---@class agents.test.SnacksList: agents.test.SnacksWindow
---@field count fun(self: agents.test.SnacksList): integer

---@class agents.test.SnacksPicker
---@field shown boolean
---@field closed boolean
---@field input agents.test.SnacksWindow
---@field list agents.test.SnacksList
---@field close fun(self: agents.test.SnacksPicker)

vim.opt.runtimepath:append(vim.env.SNACKS_DIR)
---@type { setup: fun(opts: { picker: { enabled: boolean, ui_select: boolean } }), picker: { get: fun(): agents.test.SnacksPicker[] } }
local snacks = require("snacks")
snacks.setup({ picker = { enabled = true, ui_select = false } })

local H = require("tests.helpers")
local original_input = vim.ui.input
local recipe = table.concat(vim.fn.readfile("docs/recipes/picker-snacks.md"), "\n")
local setup = assert(loadstring(assert(recipe:match("```lua\n(.-)\n```"))))

T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      setup()
      require("agents.config").get().tools = {
        cat = { name = "cat", cmd = { "cat" } },
      }
    end,
    post_case = function()
      for _, picker in ipairs(snacks.picker.get()) do
        picker:close()
      end
      vim.wait(20)
      vim.ui.input = original_input
      H.reset()
    end,
  },
})

---@return agents.test.SnacksPicker
local function current_picker()
  local picker = assert(snacks.picker.get()[1])
  H.wait(function()
    return picker.shown and picker.list:count() > 0
  end)
  return picker
end

---@param picker agents.test.SnacksPicker
---@param key string
---@param mode string
---@param win "input"|"list"
local function press(picker, key, mode, win)
  vim.api.nvim_set_current_win(assert(picker[win].win.win))
  local mapping = vim.fn.maparg(key, mode, false, true)
  local callback = mapping.callback
  assert(type(callback) == "function")
  callback()
  H.wait(function()
    return picker.closed
  end)
  -- Recipe actions run after Snacks finishes closing its windows.
  vim.wait(20)
end

---@param callback fun(opts: vim.ui.input.Opts?, on_confirm: fun(input?: string))
local function set_input(callback)
  vim.ui.input = callback
end

T["recipe tool shortcuts"] = test.new_set({
  parametrize = {
    { "<CR>", "vsplit" },
    { "<C-v>", "vsplit" },
    { "<C-x>", "split" },
    { "<C-t>", "tabnew" },
    { "<C-CR>", "current" },
    { "<C-e>", "vsplit" },
  },
}, {
  ---@param key string
  ---@param layout string
  ["launch a real session from input and list mappings"] = function(key, layout)
    ---@type { [1]: "input"|"list", [2]: "i"|"n" }[]
    local windows = { { "input", "i" }, { "list", "n" } }
    for _, from in ipairs(windows) do
      local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
      set_input(function(opts, callback)
        test.expect.equality(assert(opts).default, "cat")
        callback("cat -u")
      end)
      require("agents").new()
      press(current_picker(), key, from[2], from[1])
      local session = assert(require("agents").current())
      test.expect.equality(vim.api.nvim_get_current_win() == origin, layout == "current")
      test.expect.equality(vim.api.nvim_get_current_tabpage() == tab, layout ~= "tabnew")
      test.expect.equality(session.cmd, key == "<C-e>" and { "cat", "-u" } or { "cat" })
      test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
      require("agents").close(session.id)
    end
  end,
})

T["recipe session shortcuts"] = test.new_set({
  parametrize = {
    { "<CR>", "vsplit" },
    { "<C-v>", "vsplit" },
    { "<C-x>", "split" },
    { "<C-t>", "tabnew" },
    { "<C-CR>", "current" },
    { "<C-h>", "hide" },
    { "<C-d>", "close" },
  },
}, {
  ---@param key string
  ---@param action string
  ["show hide or close a real session through both windows"] = function(key, action)
    ---@type { [1]: "input"|"list", [2]: "i"|"n" }[]
    local windows = { { "input", "i" }, { "list", "n" } }
    for _, from in ipairs(windows) do
      local session = H.new()
      if action ~= "hide" then
        require("agents").hide(session.id)
      end
      local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
      require("agents").pick()
      press(current_picker(), key, from[2], from[1])
      if action == "close" then
        test.expect.equality(require("agents.session").get(session.id), nil)
        test.expect.equality(vim.api.nvim_buf_is_valid(session.buf), false)
      elseif action == "hide" then
        test.expect.equality(vim.fn.win_findbuf(session.buf), {})
        test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
      else
        test.expect.equality(vim.api.nvim_get_current_buf(), session.buf)
        test.expect.equality(vim.api.nvim_get_current_win() == origin, action == "current")
        test.expect.equality(vim.api.nvim_get_current_tabpage() == tab, action ~= "tabnew")
      end
      if action ~= "close" then
        require("agents").close(session.id)
      end
    end
  end,
})

return T
