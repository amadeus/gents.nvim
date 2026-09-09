local test = require("mini.test")
local T = test.new_set()
if not (vim.env.TELESCOPE_DIR and vim.env.PLENARY_DIR) then
  return T
end

-- The optional integration uses this small surface of the real Telescope API.
---@class gents.test.TelescopeManager
---@field num_results fun(self: gents.test.TelescopeManager): integer
---@field get_entry fun(self: gents.test.TelescopeManager, index: integer): gents.pickers.TelescopeEntry?

---@class gents.test.TelescopePicker
---@field prompt_title string
---@field prompt_win integer
---@field prompt_bufnr integer
---@field results_bufnr integer
---@field original_win_id integer
---@field selection_caret string
---@field manager? gents.test.TelescopeManager
---@field get_selection fun(self: gents.test.TelescopePicker): gents.pickers.TelescopeEntry?
---@field get_multi_selection fun(self: gents.test.TelescopePicker): gents.pickers.TelescopeEntry[]
---@field set_prompt fun(self: gents.test.TelescopePicker, text: string)
---@field move_selection fun(self: gents.test.TelescopePicker, change: integer)
---@field register_completion_callback fun(self: gents.test.TelescopePicker, callback: fun())
---@field clear_completion_callbacks fun(self: gents.test.TelescopePicker)

---@class gents.test.TelescopeMapping
---@field mode string
---@field keybind string
---@field desc string

---@class gents.test.TelescopeStatus
---@field picker? gents.test.TelescopePicker

---@class gents.test.TelescopeState
---@field get_existing_prompt_bufnrs fun(): integer[]
---@field get_status fun(prompt_bufnr: integer): gents.test.TelescopeStatus

vim.opt.runtimepath:append(vim.env.PLENARY_DIR)
vim.opt.runtimepath:append(vim.env.TELESCOPE_DIR)
---@type gents.test.TelescopeState
local tstate = require("telescope.state")
---@type { get_current_picker: fun(prompt_bufnr: integer): gents.test.TelescopePicker }
local action_state = require("telescope.actions.state")
---@type { which_key: fun(prompt_bufnr: integer), close: fun(prompt_bufnr: integer) }
local actions = require("telescope.actions")
---@type { get_registered_mappings: fun(prompt_bufnr: integer): gents.test.TelescopeMapping[] }
local action_utils = require("telescope.actions.utils")
---@type { values: gents.pickers.TelescopeConfigValues }
local tconfig = require("telescope.config")
---@type { default_mappings: table<string, table<string, gents.pickers.TelescopeMapping>> }
local tmappings = require("telescope.mappings")
---@type { new: fun(opts: table, defaults: table): { find: fun(self: table) } }
local tpickers = require("telescope.pickers")
---@type { new_table: fun(opts: { results: string[] }): table }
local tfinders = require("telescope.finders")

local H = require("tests.helpers")
local eq = test.expect.equality
local original_input = vim.ui.input
local original_mappings = vim.deepcopy(tconfig.values.mappings)
local original_default_mappings = tmappings.default_mappings

T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      require("gents").setup({ picker = "telescope" })
      require("gents.config").get().tools = {
        cat = { name = "cat", cmd = { "cat" } },
      }
    end,
    post_case = function()
      for _, prompt_bufnr in ipairs(tstate.get_existing_prompt_bufnrs()) do
        pcall(actions.close, prompt_bufnr)
      end
      vim.wait(20)
      vim.ui.input = original_input
      tconfig.values.mappings = vim.deepcopy(original_mappings)
      tconfig.values.default_mappings = nil
      tmappings.default_mappings = original_default_mappings
      H.reset()
    end,
  },
})

---Wait for the open picker to list the expected number of rows, or any rows.
---@param count? integer
---@return gents.test.TelescopePicker
local function current_picker(count)
  local prompt_bufnr = assert(tstate.get_existing_prompt_bufnrs()[1])
  local picker = action_state.get_current_picker(prompt_bufnr)
  H.wait(function()
    -- Telescope stores `false` until its entry manager exists.
    local manager = picker.manager
    if type(manager) ~= "table" then
      return false
    end
    local results = manager:num_results()
    if count and results ~= count then
      return false
    end
    return (results == 0 and count == 0) or picker:get_selection() ~= nil
  end)
  return picker
end

---@param picker gents.test.TelescopePicker
---@param text string
---@param count integer
local function filter(picker, text, count)
  local done = false
  picker:register_completion_callback(function()
    done = true
  end)
  picker:set_prompt(text)
  H.wait(function()
    return done and assert(picker.manager):num_results() == count
  end)
  picker:clear_completion_callbacks()
end

---Run the prompt-buffer mapping for a key without waiting for the picker to close.
---@param picker gents.test.TelescopePicker
---@param key string
---@param mode string
local function trigger(picker, key, mode)
  vim.api.nvim_set_current_win(picker.prompt_win)
  local mapping = vim.fn.maparg(key, mode, false, true)
  local callback = mapping.callback
  assert(type(callback) == "function", "no prompt mapping for " .. key)
  eq(mapping.buffer, 1)
  callback()
end

---@param picker gents.test.TelescopePicker
---@param key string
---@param mode string
local function press(picker, key, mode)
  trigger(picker, key, mode)
  H.wait(function()
    return tstate.get_status(picker.prompt_bufnr).picker == nil
  end)
  -- Adapter actions run after Telescope finishes closing its windows.
  vim.wait(20)
end

---@param picker gents.test.TelescopePicker
---@return string[] Displayed rows without their caret prefix, top to bottom.
local function rows(picker)
  ---@type string[]
  local result = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(picker.results_bufnr, 0, -1, false)) do
    if line ~= "" then
      result[#result + 1] = line:sub(#picker.selection_caret + 1)
    end
  end
  return result
end

---@param picker gents.test.TelescopePicker
---@return string[] Row text in match order, best first.
local function ordered(picker)
  ---@type string[]
  local result = {}
  local manager = assert(picker.manager)
  for index = 1, manager:num_results() do
    result[#result + 1] = assert(manager:get_entry(index)).value.text
  end
  return result
end

---@param picker gents.test.TelescopePicker
---@param namespace string
---@return { [1]: string, [2]: string }[] Highlight groups with their text, in buffer order.
local function highlights(picker, namespace)
  local buf = picker.results_bufnr
  ---@type { [1]: string, [2]: string }[]
  local result = {}
  ---@type { [1]: integer, [2]: integer, [3]: integer, [4]: { hl_group?: string, end_col?: integer, end_row?: integer } }[]
  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    vim.api.nvim_create_namespace(namespace),
    0,
    -1,
    { details = true }
  )
  for _, mark in ipairs(marks) do
    local details = mark[4]
    if details.hl_group then
      local text = vim.api.nvim_buf_get_text(
        buf,
        mark[2],
        mark[3],
        assert(details.end_row),
        assert(details.end_col),
        {}
      )
      result[#result + 1] = { details.hl_group, table.concat(text, "\n") }
    end
  end
  return result
end

---@param picker gents.test.TelescopePicker
---@return { [1]: string, [2]: string }[]
local function row_highlights(picker)
  return highlights(picker, "telescope_entry")
end

---@param picker gents.test.TelescopePicker
---@param group string
---@param text string
---@return boolean
local function has_highlight(picker, group, text)
  for _, highlight in ipairs(row_highlights(picker)) do
    if highlight[1] == group and highlight[2] == text then
      return true
    end
  end
  return false
end

---@param picker gents.test.TelescopePicker
---@return string[] Text highlighted by Telescope as matching the prompt.
local function match_highlights(picker)
  ---@type string[]
  local result = {}
  for _, highlight in ipairs(highlights(picker, "telescope_matching")) do
    eq(highlight[1], "TelescopeMatching")
    result[#result + 1] = highlight[2]
  end
  return result
end

---@param picker gents.test.TelescopePicker
---@return table<string, string> Registered mapping names by "mode key".
local function registered(picker)
  ---@type table<string, string>
  local result = {}
  for _, mapping in ipairs(action_utils.get_registered_mappings(picker.prompt_bufnr)) do
    result[mapping.mode .. " " .. mapping.keybind:lower()] = mapping.desc
  end
  return result
end

---@param picker gents.test.TelescopePicker
---@return string The text of Telescope's key hint window for the current mode.
local function help_text(picker)
  vim.api.nvim_set_current_win(picker.prompt_win)
  actions.which_key(picker.prompt_bufnr)
  ---@type string?
  local text
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:find("_TelescopeWhichKey", 1, true) and not name:find("Border", 1, true) then
      text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  -- A second call toggles the hint window off again.
  actions.which_key(picker.prompt_bufnr)
  return assert(text)
end

---@param callback fun(opts: vim.ui.input.Opts?, on_confirm: fun(input?: string))
local function set_input(callback)
  vim.ui.input = callback
end

T["shows other-tab sessions as hidden with their titles and preserves selection"] = function()
  local session = H.new({ label = "review" })
  session.title = "Investigate flaky tests"
  local session_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  require("gents").pick()
  local picker = current_picker(1)
  local directory = vim.fn.fnamemodify(session.cwd, ":~")
  local text = "○  cat · Investigate flaky tests · " .. directory
  eq(picker.prompt_title, "Gents: Sessions")
  eq(rows(picker), { text })
  eq(row_highlights(picker), {
    { "GentsPickerHidden", "○" },
    { "GentsPickerSeparator", " · " },
    { "GentsPickerSeparator", " · " },
    { "GentsPickerDirectory", directory },
  })
  eq(match_highlights(picker), {})
  filter(picker, "no-such-session-or-directory", 0)
  eq(rows(picker), {})
  filter(picker, "flaky", 1)
  eq(rows(picker), { text })
  eq(#match_highlights(picker) > 0, true)
  eq(row_highlights(picker)[4], { "GentsPickerDirectory", directory })
  press(picker, "<CR>", "i")
  eq(require("gents").current(), session)
  eq(session.label, "review")
  eq(vim.api.nvim_get_current_tabpage(), session_tab)
end

T["explicit placement"] = test.new_set({
  parametrize = {
    { "i", "<C-CR>", "current" },
    { "n", "<C-CR>", "current" },
    { "i", "<C-f>", "float" },
    { "n", "<C-f>", "float" },
  },
}, {
  ---@param mode "i"|"n"
  ---@param key string
  ---@param layout string
  ["uses the invoking tab and preserves the session view in another tab"] = function(
    mode,
    key,
    layout
  )
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.tabnew()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("gents").pick()
    press(current_picker(1), key, mode)
    eq(vim.api.nvim_get_current_win() == origin, layout == "current")
    eq(vim.api.nvim_get_current_tabpage(), tab)
    eq(vim.api.nvim_get_current_buf(), session.buf)
    if layout == "float" then
      eq(vim.api.nvim_win_get_config(0).relative, "editor")
      eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
    end
    eq(vim.api.nvim_win_get_buf(win), session.buf)
    eq(#vim.fn.win_findbuf(session.buf), 2)
    eq(require("gents").sessions(), { session })
    eq(vim.fn.jobwait({ session.job }, 0), { -1 })
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
  ["launch a real session from Insert and Normal mode mappings"] = function(key, layout)
    if layout == "float" then
      require("gents.config").get().float = {
        width = 0.5,
        height = 0.25,
        row = 1,
        col = 2,
        border = "single",
      }
    end
    for _, mode in ipairs({ "i", "n" }) do
      local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
      set_input(function(opts, callback)
        eq(assert(opts).default, "cat")
        callback("cat -u")
      end)
      require("gents").new()
      press(current_picker(1), key, mode)
      local session = assert(require("gents").current())
      eq(vim.api.nvim_get_current_win() == origin, layout == "current")
      eq(vim.api.nvim_get_current_tabpage() == tab, layout ~= "tabnew")
      eq(session.cmd, key == "<C-e>" and { "cat", "-u" } or { "cat" })
      eq(vim.fn.jobwait({ session.job }, 0), { -1 })
      if layout == "float" then
        local config = vim.api.nvim_win_get_config(0)
        eq(config.relative, "editor")
        eq(config.width, math.floor(vim.o.columns * 0.5))
        eq(config.height, math.floor(vim.o.lines * 0.25))
        eq({ config.row, config.col }, { 1, 2 })
        eq(config.border, { "┌", "─", "┐", "│", "┘", "─", "└", "│" })
      end
      require("gents").close(session.id)
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
    { "<M-h>", "hide" },
    { "<C-d>", "close" },
  },
}, {
  ---@param key string
  ---@param action string
  ["show hide or close a real session from Insert and Normal mode mappings"] = function(
    key,
    action
  )
    for _, mode in ipairs({ "i", "n" }) do
      local session = H.new()
      if action ~= "hide" then
        require("gents").hide(session.id)
      end
      local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
      require("gents").pick()
      local picker = current_picker(1)
      if action == "hide" then
        eq(row_highlights(picker), {
          { "GentsPickerVisible", "●" },
          { "GentsPickerSeparator", " · " },
          { "GentsPickerPlaceholder", "Untitled" },
          { "GentsPickerSeparator", " · " },
          { "GentsPickerDirectory", vim.fn.fnamemodify(session.cwd, ":~") },
        })
      end
      press(picker, key, mode)
      if action == "close" then
        eq(require("gents.session").get(session.id), nil)
        H.wait(function()
          return not vim.api.nvim_buf_is_valid(session.buf)
        end)
      elseif action == "hide" then
        eq(vim.fn.win_findbuf(session.buf), {})
        eq(vim.fn.jobwait({ session.job }, 0), { -1 })
        eq(vim.api.nvim_get_mode().mode, "n")
      else
        eq(vim.api.nvim_get_current_buf(), session.buf)
        eq(vim.api.nvim_get_current_win() == origin, action == "current")
        eq(vim.api.nvim_get_current_tabpage() == tab, action ~= "tabnew")
        if action == "float" then
          eq(vim.api.nvim_win_get_config(0).relative, "editor")
        end
      end
      if action ~= "close" then
        require("gents").close(session.id)
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
  ["preserves context order in the Telescope results"] = function(context, expected)
    if context ~= "empty" then
      local session = H.new()
      if context == "editor" then
        require("gents").hide(session.id)
      end
    end
    require("gents").actions()
    local picker = current_picker(#expected)
    ---@type string[]
    local names = {}
    for _, text in ipairs(ordered(picker)) do
      names[#names + 1] = assert(text:match("^(%w+)"))
    end
    eq(names, expected)
    press(picker, "<Esc>", "n")
  end,
})

T["actions picker runs the chosen command in the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("gents").hide(session.id)
  require("gents").actions()
  local picker = current_picker(7)
  eq(picker.prompt_title, "Gents: Actions")
  eq(ordered(picker)[1], "send   · Pick context to send to a session")
  eq(vim.list_contains(rows(picker), "send   · Pick context to send to a session"), true)
  eq(has_highlight(picker, "GentsPickerSeparator", " · "), true)
  eq(has_highlight(picker, "GentsPickerDescription", "Pick context to send to a session"), true)
  filter(picker, "and kill", 1)
  press(picker, "<CR>", "i")
  eq(require("gents.session").get(session.id), nil)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["actions chain into the session picker from the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("gents").hide(session.id)
  require("gents").actions()
  local picker = current_picker(7)
  filter(picker, "Existing session", 1)
  press(picker, "<CR>", "n")
  local sessions = current_picker(1)
  eq(sessions.prompt_title, "Gents: Sessions")
  eq(sessions.original_win_id, origin)
  press(sessions, "<CR>", "n")
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
end

T["context picker closes before sending the selected parts"] = function()
  local origin = vim.api.nvim_get_current_win()
  local parts = { { text = "Explain this" } }
  require("gents.config").get().prompts = { buffer = parts }
  ---@type gents.Part[]?
  local received
  ---@type boolean?
  local closed_before_action
  require("gents.picker").context(require("gents.context").capture(), function(selected)
    received = selected
    closed_before_action = #tstate.get_existing_prompt_bufnrs() == 0
  end)
  local picker = current_picker()
  eq(picker.prompt_title, "Gents: Send Context")
  eq(ordered(picker)[1]:match("^buffer%s+· Saved prompt$") ~= nil, true)
  eq(has_highlight(picker, "GentsPickerDescription", "Saved prompt"), true)
  filter(picker, "Copy entire buffer text", 1)
  filter(picker, "Saved prompt", 1)
  press(picker, "<CR>", "n")
  eq(received, parts)
  eq(closed_before_action, true)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["cancelling, empty matches, and native placement without an action do nothing"] = function()
  local session = H.new()
  require("gents").hide(session.id)
  local windows = #vim.api.nvim_list_wins()

  require("gents").pick()
  press(current_picker(1), "<Esc>", "n")
  eq(vim.fn.win_findbuf(session.buf), {})

  require("gents").pick()
  press(current_picker(1), "<C-c>", "i")
  eq(vim.fn.win_findbuf(session.buf), {})

  require("gents").pick()
  local picker = current_picker(1)
  filter(picker, "no-such-row", 0)
  trigger(picker, "<CR>", "i")
  eq(tstate.get_status(picker.prompt_bufnr).picker ~= nil, true)
  press(picker, "<Esc>", "n")
  eq(vim.fn.win_findbuf(session.buf), {})

  require("gents").actions()
  picker = current_picker(7)
  trigger(picker, "<C-v>", "i")
  eq(tstate.get_status(picker.prompt_bufnr).picker ~= nil, true)
  eq(#vim.api.nvim_list_wins() > windows, true)
  press(picker, "<Esc>", "n")
  eq(#vim.api.nvim_list_wins(), windows)
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(require("gents.session").get(session.id), session)
end

T["multi selection and quickfix keys are disabled because menus act on one row"] = function()
  local first, second = H.new(), H.new()
  require("gents").hide(first.id)
  require("gents").hide(second.id)
  local quickfix = vim.fn.getqflist()
  require("gents").pick()
  local picker = current_picker(2)
  local mappings = registered(picker)
  for _, key in ipairs({ "<tab>", "<s-tab>", "<c-q>", "<m-q>" }) do
    eq(mappings["i " .. key], "nop")
    eq(mappings["n " .. key], "nop")
  end
  trigger(picker, "<Tab>", "i")
  trigger(picker, "<C-q>", "i")
  eq(tstate.get_status(picker.prompt_bufnr).picker ~= nil, true)
  eq(picker:get_multi_selection(), {})
  eq(vim.fn.getqflist(), quickfix)
  eq(help_text(picker):find("nop", 1, true), nil)
  press(picker, "<Esc>", "n")
  eq(vim.fn.win_findbuf(first.buf), {})
  eq(vim.fn.win_findbuf(second.buf), {})
end

T["duplicate display text resolves to the selected original item once"] = function()
  ---@type string[]
  local chosen = {}
  require("gents.picker").open({
    title = "Duplicates",
    items = { { text = "same", data = "first" }, { text = "same", data = "second" } },
    default = "pick",
    actions = {
      ---@param item gents.PickerItem<string>
      pick = function(item)
        chosen[#chosen + 1] = item.data
      end,
    },
  })
  local picker = current_picker(2)
  picker:move_selection(-1)
  eq(assert(picker:get_selection()).value.data, "second")
  press(picker, "<CR>", "i")
  eq(chosen, { "second" })
end

T["native key hints list adapter mappings by name"] = function()
  local session = H.new()
  require("gents").hide(session.id)
  require("gents").pick()
  local picker = current_picker(1)
  local mappings = registered(picker)
  for _, mode in ipairs({ "i", "n" }) do
    eq(mappings[mode .. " <c-v>"], "gents_open_in_vsplit")
    eq(mappings[mode .. " <c-x>"], "gents_open_in_split")
    eq(mappings[mode .. " <c-t>"], "gents_open_in_tab")
    eq(mappings[mode .. " <c-f>"], "gents_open_in_float")
    eq(mappings[mode .. " <c-cr>"], "gents_open_here")
    eq(mappings[mode .. " <m-h>"], "gents_hide_session")
    eq(mappings[mode .. " <c-d>"], "gents_close_session")
    eq(mappings[mode .. " <c-e>"], nil)
    eq(mappings[mode .. " <cr>"], "select_default")
  end
  eq(mappings["n ?"], "which_key")
  local insert_help = false
  for key, desc in pairs(mappings) do
    insert_help = insert_help or (key:sub(1, 2) == "i " and desc == "which_key")
  end
  eq(insert_help, true)
  local help = help_text(picker)
  eq(help:find("gents_open_in_vsplit", 1, true) ~= nil, true)
  eq(help:find("gents_close_session", 1, true) ~= nil, true)
  eq(help:find("select_default", 1, true) ~= nil, true)
  press(picker, "<Esc>", "n")

  require("gents").new()
  picker = current_picker(1)
  mappings = registered(picker)
  eq(mappings["i <c-e>"], "gents_edit_command")
  eq(mappings["n <c-e>"], "gents_edit_command")
  eq(mappings["i <m-h>"], nil)
  -- Without a close action the native preview mapping stays in place.
  eq(mappings["i <c-d>"], "preview_scrolling_down")
  press(picker, "<Esc>", "n")

  require("gents").actions()
  picker = current_picker(7)
  for _, desc in pairs(registered(picker)) do
    eq(desc:find("^gents_") == nil, true)
  end
  press(picker, "<Esc>", "n")
end

T["configured Telescope mappings take precedence over adapter bindings"] = function()
  tconfig.values.mappings = {
    i = { ["<C-d>"] = "preview_scrolling_down" },
    n = { ["<c-t>"] = false, ["<Tab>"] = "move_selection_next" },
  }
  local session = H.new()
  require("gents").hide(session.id)
  require("gents").pick()
  local picker = current_picker(1)
  local mappings = registered(picker)
  eq(mappings["i <c-d>"], "preview_scrolling_down")
  eq(mappings["n <c-d>"], "gents_close_session")
  eq(mappings["n <c-t>"], nil)
  eq(mappings["i <c-t>"], "gents_open_in_tab")
  eq(mappings["n <tab>"], "move_selection_next")
  eq(mappings["i <tab>"], "nop")
  trigger(picker, "<C-d>", "i")
  eq(tstate.get_status(picker.prompt_bufnr).picker ~= nil, true)
  eq(require("gents.session").get(session.id), session)
  press(picker, "<C-d>", "n")
  eq(require("gents.session").get(session.id), nil)
end

T["replaced Telescope base mappings take precedence over adapter bindings"] = function()
  -- Telescope reads `defaults.default_mappings` once when its mappings module
  -- loads; the test applies the same table where Telescope keeps it.
  ---@type table<string, table<string, gents.pickers.TelescopeMapping>>
  local replaced = {
    i = { ["<CR>"] = "select_default", ["<C-c>"] = "close", ["<C-d>"] = "move_selection_next" },
    n = { ["<CR>"] = "select_default", ["<esc>"] = "close", ["<C-d>"] = "move_selection_next" },
  }
  tconfig.values.default_mappings = replaced
  tmappings.default_mappings = replaced
  local first, second = H.new(), H.new()
  require("gents").hide(first.id)
  require("gents").hide(second.id)
  require("gents").pick()
  local picker = current_picker(2)
  local mappings = registered(picker)
  eq(mappings["i <c-d>"], "move_selection_next")
  eq(mappings["n <c-d>"], "move_selection_next")
  eq(mappings["i <m-h>"], "gents_hide_session")
  eq(mappings["i <c-v>"], "gents_open_in_vsplit")
  local before = assert(picker:get_selection()).value
  trigger(picker, "<C-d>", "i")
  eq(tstate.get_status(picker.prompt_bufnr).picker ~= nil, true)
  eq(assert(picker:get_selection()).value ~= before, true)
  press(picker, "<Esc>", "n")
  eq(require("gents.session").get(first.id), first)
  eq(require("gents.session").get(second.id), second)
end

T["a menu requested from a Telescope mapping replaces that picker and keeps its window"] = function()
  local session = H.new()
  require("gents").hide(session.id)
  local origin = vim.api.nvim_get_current_win()
  tpickers
    .new({}, {
      prompt_title = "Probe",
      finder = tfinders.new_table({ results = { "one" } }),
      sorter = tconfig.values.generic_sorter({}),
      previewer = false,
      attach_mappings = function(_, map)
        map({ "i", "n" }, "<F6>", function()
          require("gents").pick()
        end, { desc = "gents_pick" })
        return true
      end,
    })
    :find()
  local probe = current_picker(1)
  eq(probe.prompt_title, "Probe")
  trigger(probe, "<F6>", "n")
  H.wait(function()
    return tstate.get_status(probe.prompt_bufnr).picker == nil
  end)
  local picker = current_picker(1)
  eq(picker.prompt_title, "Gents: Sessions")
  eq(picker.original_win_id, origin)
  press(picker, "<CR>", "n")
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_win_is_valid(origin), true)
  eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
end

return T
