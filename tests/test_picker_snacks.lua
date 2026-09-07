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
---@field get fun(self: agents.test.SnacksList, index: integer): agents.pickers.SnacksItem?

---@class agents.test.SnacksInput: agents.test.SnacksWindow
---@field set fun(self: agents.test.SnacksInput, pattern: string)

---@class agents.test.SnacksPicker
---@field shown boolean
---@field closed boolean
---@field input agents.test.SnacksInput
---@field list agents.test.SnacksList
---@field preview agents.test.SnacksWindow
---@field opts agents.pickers.SnacksOptions
---@field close fun(self: agents.test.SnacksPicker)
---@field find fun(self: agents.test.SnacksPicker, opts: { refresh: boolean })
---@field is_active fun(self: agents.test.SnacksPicker): boolean

---@class agents.test.SnacksLayoutNode: agents.pickers.SnacksLayoutNode
---@field box? string
---@field width? number
---@field min_width? integer
---@field height? number
---@field backdrop? boolean
---@field [integer] agents.test.SnacksLayoutNode

---@class agents.test.SnacksLayout
---@field preset? string
---@field layout? agents.test.SnacksLayoutNode
---@field config? fun(opts: agents.test.SnacksLayout)

---@class agents.test.SnacksPickerConfig
---@field layout? agents.test.SnacksLayout|fun(): agents.test.SnacksLayout
---@field win? { list: { footer_keys?: boolean, min_width?: integer, max_width?: integer } }

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
  local directory = vim.fn.fnamemodify(session.cwd, ":~")
  local text = "○  cat · Investigate flaky tests · " .. directory
  test.expect.equality(item.text, text)
  test.expect.equality(picker.opts.format(item), {
    { "○", "AgentsPickerHidden" },
    { "  cat" },
    { " · ", "AgentsPickerSeparator" },
    { "Investigate flaky tests" },
    { "" },
    { " · ", "AgentsPickerSeparator" },
    { directory, "AgentsPickerDirectory" },
  })
  local buf = vim.api.nvim_win_get_buf(assert(picker.list.win.win))
  ---@type { [1]: integer, [2]: integer, [3]: integer, [4]: { hl_group?: string, end_col?: integer, end_row?: integer } }[]
  local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
  local directory_highlighted, marker_highlighted = false, false
  local separators_highlighted = 0
  for _, mark in ipairs(marks) do
    local details = mark[4]
    if
      details.hl_group == "AgentsPickerDirectory"
      or details.hl_group == "AgentsPickerHidden"
      or details.hl_group == "AgentsPickerSeparator"
    then
      local highlighted = vim.api.nvim_buf_get_text(
        buf,
        mark[2],
        mark[3],
        assert(details.end_row),
        assert(details.end_col),
        {}
      )
      if details.hl_group == "AgentsPickerHidden" then
        test.expect.equality(highlighted, { "○" })
        marker_highlighted = true
      elseif details.hl_group == "AgentsPickerSeparator" then
        test.expect.equality(highlighted, { " · " })
        separators_highlighted = separators_highlighted + 1
      else
        test.expect.equality(highlighted, { directory })
        directory_highlighted = true
      end
    end
  end
  test.expect.equality(directory_highlighted, true)
  test.expect.equality(marker_highlighted, true)
  test.expect.equality(separators_highlighted, 2)
  picker.input:set("no-such-session-or-directory")
  picker:find({ refresh = false })
  H.wait(function()
    return not picker:is_active() and picker.list:count() == 0
  end)
  picker.input:set(directory)
  picker:find({ refresh = false })
  H.wait(function()
    return not picker:is_active() and picker.list:count() == 1
  end)
  press(picker, "<CR>", "i", "input")
  test.expect.equality(require("agents").current(), session)
  test.expect.equality(session.label, "review")
  test.expect.equality(vim.api.nvim_get_current_tabpage(), session_tab)
end

T["Snacks explicit placement"] = test.new_set({
  parametrize = {
    { "input", "i", "<C-CR>", "current" },
    { "list", "n", "<C-CR>", "current" },
    { "input", "i", "<C-f>", "float" },
    { "list", "n", "<C-f>", "float" },
  },
}, {
  ---@param from "input"|"list"
  ---@param mode "i"|"n"
  ---@param key string
  ---@param layout string
  ["uses the invoking tab and preserves the session view in another tab"] = function(
    from,
    mode,
    key,
    layout
  )
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.tabnew()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("agents").pick()
    press(current_picker(), key, mode, from)
    test.expect.equality(vim.api.nvim_get_current_win() == origin, layout == "current")
    test.expect.equality(vim.api.nvim_get_current_tabpage(), tab)
    test.expect.equality(vim.api.nvim_get_current_buf(), session.buf)
    if layout == "float" then
      test.expect.equality(vim.api.nvim_win_get_config(0).relative, "editor")
      test.expect.equality(vim.api.nvim_win_get_buf(origin) == session.buf, false)
    end
    test.expect.equality(vim.api.nvim_win_get_buf(win), session.buf)
    test.expect.equality(#vim.fn.win_findbuf(session.buf), 2)
    test.expect.equality(require("agents").sessions(), { session })
    test.expect.equality(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
})

T["built-in tool shortcuts"] = test.new_set({
  parametrize = {
    { "<CR>", "botright vsplit" },
    { "<C-v>", "vsplit" },
    { "<C-x>", "split" },
    { "<C-t>", "tabnew" },
    { "<C-f>", "float" },
    { "<C-CR>", "current" },
    { "<C-e>", "botright vsplit" },
  },
}, {
  ---@param key string
  ---@param layout string
  ["launch a real session from input and list mappings"] = function(key, layout)
    if layout == "float" then
      require("agents.config").get().float = {
        width = 0.5,
        height = 0.25,
        row = 1,
        col = 2,
        border = "single",
      }
    end
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
      if layout == "float" then
        local config = vim.api.nvim_win_get_config(0)
        test.expect.equality(config.relative, "editor")
        test.expect.equality(config.width, math.floor(vim.o.columns * 0.5))
        test.expect.equality(config.height, math.floor(vim.o.lines * 0.25))
        test.expect.equality({ config.row, config.col }, { 1, 2 })
        test.expect.equality(
          config.border,
          { "┌", "─", "┐", "│", "┘", "─", "└", "│" }
        )
      end
      require("agents").close(session.id)
    end
  end,
})

T["built-in session shortcuts"] = test.new_set({
  parametrize = {
    { "<CR>", "botright vsplit" },
    { "<C-v>", "vsplit" },
    { "<C-x>", "split" },
    { "<C-t>", "tabnew" },
    { "<C-f>", "float" },
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
      local picker = current_picker()
      if action == "hide" then
        test.expect.equality(picker.opts.format(picker.opts.items[1]), {
          { "●", "AgentsPickerVisible" },
          { "  " .. session.label },
          { " · ", "AgentsPickerSeparator" },
          { "Untitled", "AgentsPickerPlaceholder" },
          { "" },
          { " · ", "AgentsPickerSeparator" },
          { vim.fn.fnamemodify(session.cwd, ":~"), "AgentsPickerDirectory" },
        })
      end
      press(picker, key, from[2], from[1])
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
        if action == "float" then
          test.expect.equality(vim.api.nvim_win_get_config(0).relative, "editor")
        end
      end
      if action ~= "close" then
        require("agents").close(session.id)
      end
    end
  end,
})

T["actions ordering"] = test.new_set({
  parametrize = {
    { "empty", { "new", "send" } },
    { "session", { "focus", "hide", "toggle", "close", "pick", "send", "new" } },
    { "editor", { "send", "toggle", "focus", "pick", "hide", "close", "new" } },
  },
}, {
  ---@param context string
  ---@param expected string[]
  ["preserves context order in the visible Snacks list"] = function(context, expected)
    if context ~= "empty" then
      local session = H.new()
      if context == "editor" then
        require("agents").hide(session.id)
      end
    end
    require("agents").actions()
    local picker = current_picker()
    H.wait(function()
      return not picker:is_active()
    end)
    ---@type string[]
    local names = {}
    for index = 1, picker.list:count() do
      local item = assert(picker.list:get(index))
      names[#names + 1] = assert(item.text:match("^(%w+)"))
    end
    test.expect.equality(names, expected)
  end,
})

T["actions picker runs the chosen command in the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").actions()
  local picker = current_picker()
  test.expect.equality(picker.opts.title, "Agents: Actions")
  test.expect.equality(picker.opts.confirm, "agents_run")
  test.expect.equality(picker.opts.items[1].text, "send   · Pick context to send to a session")
  test.expect.equality(picker.opts.format(picker.opts.items[1]), {
    { "send  " },
    { " · ", "AgentsPickerSeparator" },
    { "Pick context to send to a session", "AgentsPickerDescription" },
  })
  picker.input:set("and kill")
  picker:find({ refresh = false })
  H.wait(function()
    return not picker:is_active() and picker.list:count() == 1
  end)
  press(picker, "<CR>", "i", "input")
  test.expect.equality(require("agents.session").get(session.id), nil)
  test.expect.equality(vim.api.nvim_get_current_win(), origin)
end

T["context picker preserves previews and closes before sending the selected parts"] = function()
  local origin = vim.api.nvim_get_current_win()
  local parts = { { text = "Explain this" } }
  require("agents.config").get().prompts = { buffer = parts }
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
  local item = picker.opts.items[1]
  local chunks = picker.opts.format(item)
  test.expect.equality(vim.trim(chunks[1][1]), "buffer")
  test.expect.equality(chunks[2], { " · ", "AgentsPickerSeparator" })
  test.expect.equality(chunks[3], { "Saved prompt", "AgentsPickerDescription" })
  test.expect.equality(item.text, chunks[1][1] .. " · Saved prompt")
  test.expect.equality(item.preview, { text = "Explain this" })
  picker.input:set("Copy entire buffer text")
  picker:find({ refresh = false })
  H.wait(function()
    return not picker:is_active() and picker.list:count() == 1
  end)
  picker.input:set("Saved prompt")
  picker:find({ refresh = false })
  H.wait(function()
    return not picker:is_active() and picker.list:count() == 1
  end)
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

T["chunk formatting preserves plain highlights and returns fresh arrays"] = function()
  ---@type agents.PickerChunk[]
  local chunks = {
    { text = "v", kind = "visible" },
    { text = "  Example  " },
    { text = "/tmp/project", kind = "directory" },
    { text = "  custom args" },
  }
  local original = vim.deepcopy(chunks)
  require("agents.picker").open({
    title = "Styled item",
    items = {
      { text = "v  Example  /tmp/project  custom args", data = 1, hl = "Comment", chunks = chunks },
    },
    default = "show",
    actions = { show = function() end },
  })
  local picker = current_picker()
  local item = picker.opts.items[1]
  local expected = {
    { "v", "AgentsPickerVisible" },
    { "  Example  ", "Comment" },
    { "/tmp/project", "AgentsPickerDirectory" },
    { "  custom args", "Comment" },
  }
  local formatted = picker.opts.format(item)
  test.expect.equality(formatted, expected)
  -- Snacks may trim or resolve the returned chunks while rendering a row.
  formatted[1][1] = "changed"
  table.remove(formatted)
  test.expect.equality(picker.opts.format(item), expected)
  test.expect.equality(chunks, original)
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
          width = 30,
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
      tools = "  C-v  vsplit   C-x  split   C-t  tab   C-f  float   C-Ent  here   C-e  args  ",
      sessions = "  C-v  vsplit   C-x  split   C-t  tab   C-f  float   C-Ent  here   C-h  hide   C-d  close  ",
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
      if bordered then
        test.expect.equality(config.width, 30)
      end
    end
  end,
})

T["binding footer preserves wider dropdown sizing and borders across resizing"] = function()
  vim.o.columns = 200
  local input_border = { "┌", "─", "┐", "│", "┤", "─", "├", "│" }
  local list_border = { "", "", "", "│", "┘", "─", "└", "│" }
  snacks.config.picker.layout = {
    preset = "dropdown",
    layout = {
      backdrop = false,
      width = 0.5,
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
  test.expect.equality(width, 98)
  test.expect.equality(width >= vim.fn.strdisplaywidth(footer) + 2, true)
  test.expect.equality(vim.api.nvim_win_get_config(list_win).border, list_border)
  test.expect.equality(vim.api.nvim_win_get_config(input_win).border, input_border)

  vim.o.columns = 240
  vim.api.nvim_exec_autocmds("VimResized", {})
  H.wait(function()
    return vim.api.nvim_win_get_width(assert(picker.list.win.win)) > width
  end)
  test.expect.equality(vim.api.nvim_win_get_width(assert(picker.list.win.win)), 118)
  test.expect.equality(footer_text(picker), footer)
  test.expect.equality(vim.api.nvim_win_get_config(assert(picker.list.win.win)).border, list_border)
end

T["binding footer widens a narrow dropdown and remains bounded across screen resizing"] = function()
  vim.o.columns = 200
  local border = { "", "", "", "│", "┘", "─", "└", "│" }
  snacks.config.picker.layout = {
    preset = "dropdown",
    layout = {
      box = "vertical",
      width = 0.2,
      min_width = 30,
      height = 10,
      border = "none",
      { win = "input", height = 1, border = "bottom" },
      { win = "list", border = border },
    },
  }
  H.new()
  require("agents").pick()
  local picker = current_picker()
  local footer = footer_text(picker)
  local required = vim.fn.strdisplaywidth(footer) + 2
  test.expect.equality(vim.api.nvim_win_get_width(assert(picker.list.win.win)) >= required, true)

  vim.o.columns = 40
  vim.api.nvim_exec_autocmds("VimResized", {})
  H.wait(function()
    return vim.api.nvim_win_get_width(assert(picker.list.win.win)) <= 38
  end)
  test.expect.equality(footer_text(picker), footer)
  test.expect.equality(vim.api.nvim_win_get_config(assert(picker.list.win.win)).border, border)

  vim.o.columns = 200
  vim.api.nvim_exec_autocmds("VimResized", {})
  H.wait(function()
    return vim.api.nvim_win_get_width(assert(picker.list.win.win)) >= required
  end)
  test.expect.equality(footer_text(picker), footer)
  test.expect.equality(vim.api.nvim_win_get_config(assert(picker.list.win.win)).border, border)
end

T["binding footer with a horizontal preview"] = test.new_set({
  parametrize = { { 0.5 }, { 60 }, { 0 } },
}, {
  ---@param preview_width number
  ["fits when possible and keeps both panes inside a smaller screen"] = function(preview_width)
    vim.o.columns = 240
    snacks.config.picker.layout = {
      layout = {
        box = "horizontal",
        width = 0.5,
        height = 10,
        border = "none",
        {
          box = "vertical",
          border = "rounded",
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        { win = "preview", width = preview_width, border = "rounded" },
      },
    }
    H.new()
    require("agents").pick()
    local picker = current_picker()
    local required = vim.fn.strdisplaywidth(footer_text(picker)) + 2

    ---@return boolean
    local function inside_screen()
      -- Floating-window screen positions refresh on redraw after replacing the layout root.
      vim.cmd.redraw()
      local list_win, preview_win = assert(picker.list.win.win), assert(picker.preview.win.win)
      local list_col = vim.api.nvim_win_get_position(list_win)[2]
      local preview_col = vim.api.nvim_win_get_position(preview_win)[2]
      return list_col >= 0
        and preview_col > list_col + vim.api.nvim_win_get_width(list_win)
        and preview_col + vim.api.nvim_win_get_width(preview_win) + 2 <= vim.o.columns
    end

    test.expect.equality(vim.api.nvim_win_get_width(assert(picker.list.win.win)) >= required, true)
    test.expect.equality(inside_screen(), true)
    vim.o.columns = 80
    vim.api.nvim_exec_autocmds("VimResized", {})
    H.wait(inside_screen)
    test.expect.equality(vim.api.nvim_win_get_width(assert(picker.preview.win.win)) > 0, true)
    vim.o.columns = 240
    vim.api.nvim_exec_autocmds("VimResized", {})
    H.wait(function()
      return vim.api.nvim_win_get_width(assert(picker.list.win.win)) >= required
    end)
    test.expect.equality(inside_screen(), true)
  end,
})

T["binding footer widens the sidebar preset while keeping the source editor"] = function()
  vim.o.columns = 200
  local origin, source = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  snacks.config.picker.layout = { preset = "sidebar" }
  require("agents").new()
  local picker = current_picker()
  test.expect.equality(
    vim.api.nvim_win_get_width(assert(picker.list.win.win))
      >= vim.fn.strdisplaywidth(footer_text(picker)) + 2,
    true
  )
  test.expect.equality(vim.api.nvim_win_is_valid(origin), true)
  test.expect.equality(vim.api.nvim_win_get_buf(origin), source)
  test.expect.equality(vim.api.nvim_win_get_width(origin) > 0, true)
end

T["binding footer lifts a conflicting list window width limit"] = function()
  vim.o.columns = 200
  snacks.config.picker.win = { list = { min_width = 30, max_width = 40 } }
  snacks.config.picker.layout = {
    layout = {
      box = "vertical",
      width = 100,
      height = 10,
      border = "none",
      { win = "input", height = 1, border = "bottom" },
      { win = "list", border = "none" },
    },
  }
  require("agents").new()
  local picker = current_picker()
  test.expect.equality(
    vim.api.nvim_win_get_width(assert(picker.list.win.win))
      >= vim.fn.strdisplaywidth(footer_text(picker)) + 2,
    true
  )
end

T["binding footer preserves a dynamic layout and runs its configuration hook once"] = function()
  vim.o.columns = 200
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
        assert(opts.layout).width = 30
      end,
    }
  end
  require("agents").new()
  local picker = current_picker()
  test.expect.equality({ resolved, configured }, { 1, 1 })
  test.expect.equality(
    vim.api.nvim_win_get_width(assert(picker.list.win.win))
      >= vim.fn.strdisplaywidth(footer_text(picker)) + 2,
    true
  )
  test.expect.equality(
    footer_text(picker),
    "  C-v  vsplit   C-x  split   C-t  tab   C-f  float   C-Ent  here   C-e  args  "
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
      "  C-v  vsplit   C-x  split   C-t  tab   C-f  float   C-Ent  here   C-e  args  "
    )
    test.expect.equality(vim.api.nvim_win_get_config(assert(picker.list.win.win)).border, expected)
  end,
})

T["binding footer takes precedence over Snacks automatic key hints"] = function()
  snacks.config.picker.win = { list = { footer_keys = true } }
  require("agents").new()
  test.expect.equality(
    footer_text(current_picker()),
    "  C-v  vsplit   C-x  split   C-t  tab   C-f  float   C-Ent  here   C-e  args  "
  )
end

T["hidden binding hints preserve layout and shortcuts"] = function()
  require("agents.config").get().picker_help = false
  snacks.config.picker.win = { list = { footer_keys = true } }
  snacks.config.picker.layout = {
    layout = {
      box = "vertical",
      width = 40,
      height = 10,
      border = "none",
      { win = "input", height = 1, border = "bottom" },
      { win = "list", border = "none" },
    },
  }
  local session = H.new()
  require("agents").pick()
  local picker = current_picker()
  local config = vim.api.nvim_win_get_config(assert(picker.list.win.win))
  test.expect.equality(config.footer, nil)
  test.expect.equality(config.border, "none")
  test.expect.equality(config.width, 40)
  for _, win in ipairs({ picker.input.win, picker.list.win }) do
    vim.api.nvim_set_current_win(assert(win.win))
    for _, mode in ipairs({ "n", "i" }) do
      for _, key in ipairs({
        "<CR>",
        "<C-v>",
        "<C-x>",
        "<C-t>",
        "<C-f>",
        "<C-CR>",
        "<C-h>",
        "<C-d>",
      }) do
        test.expect.equality(type(vim.fn.maparg(key, mode, false, true).callback), "function")
      end
    end
  end
  test.expect.equality(vim.fn.maparg("?", "n", false, true).desc, "toggle_help_list")
  press(picker, "<C-h>", "i", "input")
  test.expect.equality(require("agents.window").visible(session), false)
  test.expect.equality(require("agents.session").get(session.id), session)
end

return T
