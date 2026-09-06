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
---@field opts agents.pickers.SnacksOptions
---@field close fun(self: agents.test.SnacksPicker)

---@class agents.test.SnacksLayoutNode: agents.pickers.SnacksLayoutNode
---@field box? string
---@field width? number
---@field min_width? integer
---@field height? number
---@field backdrop? boolean
---@field [integer] agents.test.SnacksLayoutNode

---@class agents.test.SnacksLayout
---@field preset? string
---@field layout agents.test.SnacksLayoutNode
---@field config? fun(opts: agents.test.SnacksLayout)

---@class agents.test.SnacksPickerConfig
---@field layout? agents.test.SnacksLayout|fun(): agents.test.SnacksLayout
---@field win? { list: { footer_keys?: boolean } }

vim.opt.runtimepath:append(vim.env.SNACKS_DIR)
---@type { setup: fun(opts: { picker: { enabled: boolean, ui_select: boolean } }), picker: { get: fun(): agents.test.SnacksPicker[] }, config: { picker: agents.test.SnacksPickerConfig } }
local snacks = require("snacks")
snacks.setup({ picker = { enabled = true, ui_select = false } })

local H = require("tests.helpers")
local original_input = vim.ui.input
local original_layout = snacks.config.picker.layout
local original_win = snacks.config.picker.win
local original_columns = vim.o.columns
local original_winborder = vim.o.winborder

T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      require("agents").setup({ picker = "snacks" })
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
      snacks.config.picker.layout = original_layout
      snacks.config.picker.win = original_win
      vim.o.columns = original_columns
      vim.o.winborder = original_winborder
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
  -- Adapter actions run after Snacks finishes closing its windows.
  vim.wait(20)
end

---@param callback fun(opts: vim.ui.input.Opts?, on_confirm: fun(input?: string))
local function set_input(callback)
  vim.ui.input = callback
end

---@param picker agents.test.SnacksPicker
---@return agents.pickers.SnacksHighlight[]
local function footer_chunks(picker)
  ---@type agents.pickers.SnacksHighlight[]
  local footer = vim.api.nvim_win_get_config(assert(picker.list.win.win)).footer or {}
  return footer
end

---@param picker agents.test.SnacksPicker
---@return string
local function footer_text(picker)
  ---@type string[]
  local text = {}
  for _, chunk in ipairs(footer_chunks(picker)) do
    text[#text + 1] = chunk[1]
  end
  return table.concat(text)
end

T["Snacks shows other-tab sessions as hidden with their titles and preserves selection"] = function()
  local session = H.new({ label = "review" })
  session.title = "Investigate flaky tests"
  local session_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  require("agents").pick()
  local picker = current_picker()
  local item = picker.opts.items[1]
  local text = "review · Investigate flaky tests  [hidden]  " .. session.cwd
  test.expect.equality(item.text, text)
  test.expect.equality(picker.opts.format(item)[1][1], text)
  press(picker, "<CR>", "i", "input")
  test.expect.equality(require("agents").current(), session)
  test.expect.equality(vim.api.nvim_get_current_tabpage(), session_tab)
end

T["built-in tool shortcuts"] = test.new_set({
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

T["built-in session shortcuts"] = test.new_set({
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
        H.wait(function()
          return not vim.api.nvim_buf_is_valid(session.buf)
        end)
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

T["actions picker runs the chosen command in the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").actions()
  local picker = current_picker()
  test.expect.equality(picker.opts.title, "Agents: actions")
  test.expect.equality(picker.opts.confirm, "agents_run")
  test.expect.equality(picker.opts.items[1].text, "close")
  press(picker, "<CR>", "i", "input")
  test.expect.equality(require("agents.session").get(session.id), nil)
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
end

T["context picker preserves previews and closes before sending the selected parts"] = function()
  local origin = vim.api.nvim_get_current_win()
  local parts = { { text = "Explain this" } }
  require("agents.config").get().prompts = { explain = parts }
  ---@type agents.Part[]?
  local received
  ---@type boolean?
  local closed_before_action
  require("agents.picker").context(require("agents.context").capture(), function(selected)
    received = selected
    closed_before_action = #snacks.picker.get() == 0
  end)
  local picker = current_picker()
  test.expect.equality(picker.opts.confirm, "agents_send")
  test.expect.equality(picker.opts.items[1].text, "explain [prompt]")
  test.expect.equality(picker.opts.items[1].preview, { text = "Explain this" })
  press(picker, "<CR>", "n", "list")
  test.expect.equality(received, parts)
  test.expect.equality(closed_before_action, true)
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
end

T["item formatting preserves the suggested highlight"] = function()
  require("agents.picker").open({
    title = "Highlighted item",
    items = { { text = "Missing tool", data = 1, hl = "Comment" } },
    default = "new",
    actions = { new = function() end },
  })
  local picker = current_picker()
  test.expect.equality(picker.opts.format(picker.opts.items[1]), { { "Missing tool", "Comment" } })
  test.expect.equality(picker.opts.actions.agents_vsplit, nil)
end

T["binding footer"] = test.new_set({
  parametrize = {
    { "tools" },
    { "sessions" },
    { "actions" },
    { "context" },
    { "actions", true },
    { "context", true },
  },
}, {
  ---@param kind string
  ---@param bordered? boolean
  ["shows only non-default picker actions and omits empty footers"] = function(kind, bordered)
    if bordered then
      snacks.config.picker.layout = {
        layout = {
          box = "vertical",
          width = 70,
          height = 10,
          border = "none",
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "bottom" },
        },
      }
    end
    if kind == "tools" then
      require("agents").new()
    elseif kind == "sessions" then
      H.new()
      require("agents").pick()
    elseif kind == "actions" then
      require("agents").actions()
    else
      require("agents.config").get().prompts = { explain = { { text = "Explain this" } } }
      require("agents.picker").context(require("agents.context").capture(), function() end)
    end
    local picker = current_picker()
    local footer = footer_text(picker)
    ---@type table<string, string>
    local expected = {
      tools = "  C-v  vsplit   C-x  split   C-t  tab   C-Ent  here   C-e  args  ",
      sessions = "  C-v  vsplit   C-x  split   C-t  tab   C-Ent  here   C-h  hide   C-d  close  ",
      actions = "",
      context = "",
    }
    test.expect.equality(footer, expected[kind])
    local chunks = footer_chunks(picker)
    if #chunks > 0 then
      test.expect.equality(
        vim.api.nvim_win_get_config(assert(picker.list.win.win)).footer_pos,
        "center"
      )
      test.expect.equality(
        { chunks[1], chunks[#chunks] },
        { { " ", "SnacksFooter" }, { " ", "SnacksFooter" } }
      )
    end
    for _, chunk in ipairs(chunks) do
      if chunk[2] == "SnacksFooterKey" or chunk[2] == "SnacksFooterDesc" then
        test.expect.equality(chunk[1], " " .. vim.trim(chunk[1]) .. " ")
      else
        test.expect.equality(chunk, { " ", "SnacksFooter" })
      end
    end
    -- Snacks' complete keybinding help remains available from the list.
    vim.api.nvim_set_current_win(assert(picker.list.win.win))
    test.expect.equality(vim.fn.maparg("?", "n", false, true).desc, "toggle_help_list")
    test.expect.equality(type(vim.fn.maparg("<CR>", "n", false, true).callback), "function")
    if kind == "actions" or kind == "context" then
      local config = vim.api.nvim_win_get_config(assert(picker.list.win.win))
      test.expect.equality(config.footer, nil)
      test.expect.equality(
        config.border,
        bordered and { "", "", "", "", "", "─", "", "" } or "none"
      )
    end
  end,
})

T["binding footer preserves dropdown sizing and borders across resizing"] = function()
  vim.o.columns = 200
  local input_border = { "┌", "─", "┐", "│", "┤", "─", "├", "│" }
  local list_border = { "", "", "", "│", "┘", "─", "└", "│" }
  snacks.config.picker.layout = {
    preset = "dropdown",
    layout = {
      backdrop = false,
      width = 0.4,
      min_width = 80,
      height = 10,
      border = "none",
      box = "vertical",
      { win = "input", height = 1, border = input_border },
      { win = "list", border = list_border },
    },
  }
  H.new()
  require("agents").pick()
  local picker = current_picker()
  local list_win, input_win = assert(picker.list.win.win), assert(picker.input.win.win)
  local footer = footer_text(picker)
  local width = vim.api.nvim_win_get_width(list_win)
  test.expect.equality(width <= 80, true)
  test.expect.equality(vim.api.nvim_win_get_config(list_win).border, list_border)
  test.expect.equality(vim.api.nvim_win_get_config(input_win).border, input_border)

  vim.o.columns = 240
  vim.api.nvim_exec_autocmds("VimResized", {})
  H.wait(function()
    return vim.api.nvim_win_get_width(list_win) > width
  end)
  test.expect.equality(footer_text(picker), footer)
  test.expect.equality(vim.api.nvim_win_get_config(list_win).border, list_border)
end

T["binding footer preserves a dynamic layout and runs its configuration hook once"] = function()
  local resolved, configured = 0, 0
  local layout = {
    box = "vertical",
    width = 80,
    height = 10,
    border = "none",
    { win = "input", height = 1, border = "bottom" },
    { win = "list", border = "none" },
  }
  snacks.config.picker.layout = function()
    resolved = resolved + 1
    return {
      layout = layout,
      ---@param opts agents.test.SnacksLayout
      config = function(opts)
        configured = configured + 1
        opts.layout.width = 70
      end,
    }
  end
  require("agents").new()
  local picker = current_picker()
  test.expect.equality({ resolved, configured }, { 1, 1 })
  test.expect.equality(vim.api.nvim_win_get_width(assert(picker.list.win.win)), 70)
  test.expect.equality(
    footer_text(picker),
    "  C-v  vsplit   C-x  split   C-t  tab   C-Ent  here   C-e  args  "
  )
  test.expect.equality(layout[2].border, "none")
end

T["binding footer border"] = test.new_set({
  parametrize = {
    { "", { "", "", "", "", "", "─", "", "" } },
    { "hpad", { "", "", "", " ", " ", "─", " ", " " } },
    { "top", { "", "─", "", "", "", "─", "", "" } },
    {
      { "╭", "━", "╮", "┃", "", "", "", "┃" },
      { "╭", "━", "╮", "┃", " ", "─", " ", "┃" },
    },
    { true, { "╭", "━", "╮", "┃", " ", "─", " ", "┃" } },
  },
}, {
  ---@param border string|string[]|boolean
  ---@param expected string[]
  ["adds a missing bottom edge while preserving existing edges"] = function(border, expected)
    if border == true then
      local supported = pcall(function()
        vim.o.winborder = "╭,━,╮,┃,,,,┃"
      end)
      if not supported then
        test.skip("This Neovim version rejects empty entries in the winborder option")
      end
    end
    snacks.config.picker.layout = {
      layout = {
        box = "vertical",
        width = 70,
        height = 10,
        border = "none",
        { win = "input", height = 1, border = "bottom" },
        { win = "list", border = border },
      },
    }
    require("agents").new()
    local picker = current_picker()
    test.expect.equality(
      footer_text(picker),
      "  C-v  vsplit   C-x  split   C-t  tab   C-Ent  here   C-e  args  "
    )
    test.expect.equality(vim.api.nvim_win_get_config(assert(picker.list.win.win)).border, expected)
  end,
})

T["binding footer takes precedence over Snacks automatic key hints"] = function()
  snacks.config.picker.win = { list = { footer_keys = true } }
  require("agents").new()
  test.expect.equality(
    footer_text(current_picker()),
    "  C-v  vsplit   C-x  split   C-t  tab   C-Ent  here   C-e  args  "
  )
end

return T
