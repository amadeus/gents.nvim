local test = require("mini.test")
local T = test.new_set()
if not vim.env.MINI_PICK_DIR then
  return T
end

-- The optional integration uses this small surface of the real mini.pick API.
---@class agents.test.MiniPickState
---@field buffers { main: integer, preview?: integer, info?: integer }
---@field windows { main: integer, target: integer }
---@field is_busy boolean

---@class agents.test.MiniPickMatches
---@field all? agents.pickers.MiniItem[]
---@field current? agents.pickers.MiniItem
---@field marked? agents.pickers.MiniItem[]

---@class agents.test.MiniPick
---@field config { mappings: agents.pickers.MiniMappings }
---@field setup fun(config?: table)
---@field stop fun()
---@field is_picker_active fun(): boolean
---@field get_picker_state fun(): agents.test.MiniPickState?
---@field get_picker_items fun(): agents.pickers.MiniItem[]?
---@field get_picker_matches fun(): agents.test.MiniPickMatches?
---@field get_picker_query fun(): string[]?
---@field get_picker_opts fun(): { source: { name: string } }?

vim.opt.runtimepath:append(vim.env.MINI_PICK_DIR)
local original_select = vim.ui.select
---@type agents.test.MiniPick
local mini = require("mini.pick")
mini.setup()
-- mini.pick replaces vim.ui.select during setup; the other suites use the original.
vim.ui.select = original_select

local H = require("tests.helpers")
local eq = test.expect.equality
local original_input = vim.ui.input
local original_mappings = vim.deepcopy(mini.config.mappings)
local original_showmode = vim.o.showmode
local namespace = vim.api.nvim_create_namespace("agents.pickers.mini")
-- mini.pick creates its namespaces by name, so the same call returns its id.
local ranges = vim.api.nvim_create_namespace("MiniPickRanges")

---@alias agents.test.MiniStep string|fun(): boolean?

---@type agents.test.MiniStep[]
local steps = {}
---@type string?
local failure
local timer = assert(vim.uv.new_timer())

---Drive the pickers opened by the next blocking call: strings are typed into a
---ready picker, functions run every tick until they return true. A failing or
---stalled step stops the picker so MiniPick.start() returns and finish() can
---report the failure.
---@param list agents.test.MiniStep[]
local function drive(list)
  steps, failure = list, nil
  local waited = 0
  timer:start(
    0,
    5,
    vim.schedule_wrap(function()
      local state = mini.get_picker_state()
      if not state or state.is_busy or mini.get_picker_items() == nil then
        return
      end
      local step = steps[1]
      local ok, result = pcall(function()
        if type(step) == "string" then
          -- Input is consumed by the picker before the next tick runs.
          vim.api.nvim_input(step)
          return true
        end
        return step and step()
      end)
      if not ok then
        failure = tostring(result)
      elseif result then
        table.remove(steps, 1)
        waited = 0
        return
      else
        waited = waited + 1
        if waited < 400 then
          return
        end
        failure = step and "timed out waiting for a picker step" or "picker left open without steps"
      end
      steps = {}
      mini.stop()
    end)
  )
end

---Assert that every driven step completed after the blocking picker call returned.
local function finish()
  timer:stop()
  assert(failure == nil, failure)
  eq(#steps, 0)
  eq(mini.is_picker_active(), false)
end

T = test.new_set({
  hooks = {
    pre_once = function()
      -- Headless redraws print mode messages while a session is in terminal mode.
      vim.o.showmode = false
    end,
    post_once = function()
      vim.o.showmode = original_showmode
    end,
    pre_case = function()
      H.reset()
      require("agents").setup({ picker = "mini" })
      require("agents.config").get().tools = {
        cat = { name = "cat", cmd = { "cat" } },
      }
    end,
    post_case = function()
      timer:stop()
      steps = {}
      vim.ui.input = original_input
      mini.config.mappings = vim.deepcopy(original_mappings)
      vim.b.minipick_config = nil
      H.reset()
    end,
  },
})

---@return integer
local function main_buffer()
  return assert(mini.get_picker_state()).buffers.main
end

---@return string[]
local function rows()
  return vim.api.nvim_buf_get_lines(main_buffer(), 0, -1, false)
end

---@param buf integer
---@param ns integer
---@return { [1]: string, [2]: string }[] Highlight groups with their text, in buffer order.
local function highlights(buf, ns)
  ---@type { [1]: string, [2]: string }[]
  local result = {}
  ---@type { [1]: integer, [2]: integer, [3]: integer, [4]: { hl_group?: string, end_col?: integer, end_row?: integer } }[]
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
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

---@return { [1]: string, [2]: string }[]
local function row_highlights()
  return highlights(main_buffer(), namespace)
end

---@return string[] Text highlighted by mini.pick as matching the query.
local function match_highlights()
  ---@type string[]
  local result = {}
  for _, highlight in ipairs(highlights(main_buffer(), ranges)) do
    eq(highlight[1], "MiniPickMatchRanges")
    result[#result + 1] = highlight[2]
  end
  return result
end

---@param query string
---@return boolean
local function typed(query)
  return table.concat(assert(mini.get_picker_query())) == query
end

---@return agents.pickers.MiniItem[]
local function matches()
  return assert(assert(mini.get_picker_matches()).all)
end

---@return string[]? Info view lines once the view is shown.
local function info_lines()
  local info = assert(mini.get_picker_state()).buffers.info
  return info and vim.api.nvim_buf_get_lines(info, 0, -1, false) or nil
end

---@param lines string[]
---@param description string
---@return string? The key listed in the info view for a mapping description.
local function mapping_key(lines, description)
  for _, line in ipairs(lines) do
    local name, key = line:match("^(.-)%s+│ (.+)$")
    if name == description then
      return key
    end
  end
  return nil
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
  local directory = vim.fn.fnamemodify(session.cwd, ":~")
  local text = "○  cat · Investigate flaky tests · " .. directory
  drive({
    function()
      eq(assert(mini.get_picker_opts()).source.name, "Agents: Sessions")
      eq(rows(), { text })
      eq(row_highlights(), {
        { "AgentsPickerHidden", "○" },
        { "AgentsPickerSeparator", " · " },
        { "AgentsPickerSeparator", " · " },
        { "AgentsPickerDirectory", directory },
      })
      eq(match_highlights(), {})
      ---@type { [1]: integer, [2]: integer, [3]: integer, [4]: { priority?: integer } }[]
      local marks =
        vim.api.nvim_buf_get_extmarks(main_buffer(), namespace, 0, -1, { details = true })
      eq(#marks, 4)
      for _, mark in ipairs(marks) do
        -- Below mini.pick's match highlighting so matches stay visible.
        eq(assert(mark[4].priority) < 200, true)
      end
      return true
    end,
    "no-such-session-or-directory",
    function()
      if not typed("no-such-session-or-directory") then
        return false
      end
      eq(matches(), {})
      eq(rows(), { "" })
      return true
    end,
    "<C-u>flaky",
    function()
      if not typed("flaky") then
        return false
      end
      eq(#matches(), 1)
      eq(rows(), { text })
      eq(match_highlights(), { "f", "l", "a", "k", "y" })
      eq(row_highlights()[4], { "AgentsPickerDirectory", directory })
      return true
    end,
    "<CR>",
  })
  require("agents").pick()
  finish()
  eq(require("agents").current(), session)
  eq(session.label, "review")
  eq(vim.api.nvim_get_current_tabpage(), session_tab)
end

T["explicit placement"] = test.new_set({
  parametrize = { { "<C-CR>", "current" }, { "<M-f>", "float" } },
}, {
  ---@param key string
  ---@param layout string
  ["uses the invoking tab and preserves the session view in another tab"] = function(key, layout)
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.tabnew()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    drive({ key })
    require("agents").pick()
    finish()
    eq(vim.api.nvim_get_current_win() == origin, layout == "current")
    eq(vim.api.nvim_get_current_tabpage(), tab)
    eq(vim.api.nvim_get_current_buf(), session.buf)
    if layout == "float" then
      eq(vim.api.nvim_win_get_config(0).relative, "editor")
      eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
    end
    eq(vim.api.nvim_win_get_buf(win), session.buf)
    eq(#vim.fn.win_findbuf(session.buf), 2)
    eq(require("agents").sessions(), { session })
    eq(vim.fn.jobwait({ session.job }, 0), { -1 })
  end,
})

T["built-in tool shortcuts"] = test.new_set({
  parametrize = {
    { "<CR>", "botright vsplit" },
    { "<C-v>", "vsplit" },
    { "<C-s>", "split" },
    { "<C-t>", "tabnew" },
    { "<M-f>", "float" },
    { "<C-CR>", "current" },
    { "<C-e>", "botright vsplit" },
  },
}, {
  ---@param key string
  ---@param layout string
  ["launch a real session"] = function(key, layout)
    if layout == "float" then
      require("agents.config").get().float = {
        width = 0.5,
        height = 0.25,
        row = 1,
        col = 2,
        border = "single",
      }
    end
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    set_input(function(opts, callback)
      eq(assert(opts).default, "cat")
      callback("cat -u")
    end)
    drive({ key })
    require("agents").new()
    finish()
    local session = assert(require("agents").current())
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
  end,
})

T["built-in session shortcuts"] = test.new_set({
  parametrize = {
    { "<CR>", "botright vsplit" },
    { "<C-v>", "vsplit" },
    { "<C-s>", "split" },
    { "<C-t>", "tabnew" },
    { "<M-f>", "float" },
    { "<C-CR>", "current" },
    { "<M-h>", "hide" },
    { "<C-d>", "close" },
  },
}, {
  ---@param key string
  ---@param action string
  ["show hide or close a real session"] = function(key, action)
    local session = H.new()
    if action ~= "hide" then
      require("agents").hide(session.id)
    end
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    drive({
      function()
        if action == "hide" then
          eq(row_highlights(), {
            { "AgentsPickerVisible", "●" },
            { "AgentsPickerSeparator", " · " },
            { "AgentsPickerPlaceholder", "Untitled" },
            { "AgentsPickerSeparator", " · " },
            { "AgentsPickerDirectory", vim.fn.fnamemodify(session.cwd, ":~") },
          })
        end
        return true
      end,
      key,
    })
    require("agents").pick()
    finish()
    if action == "close" then
      eq(require("agents.session").get(session.id), nil)
      H.wait(function()
        return not vim.api.nvim_buf_is_valid(session.buf)
      end)
    elseif action == "hide" then
      eq(vim.fn.win_findbuf(session.buf), {})
      eq(vim.fn.jobwait({ session.job }, 0), { -1 })
    else
      eq(vim.api.nvim_get_current_buf(), session.buf)
      eq(vim.api.nvim_get_current_win() == origin, action == "current")
      eq(vim.api.nvim_get_current_tabpage() == tab, action ~= "tabnew")
      if action == "float" then
        eq(vim.api.nvim_win_get_config(0).relative, "editor")
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
  ["preserves context order in the visible list"] = function(context, expected)
    if context ~= "empty" then
      local session = H.new()
      if context == "editor" then
        require("agents").hide(session.id)
      end
    end
    drive({
      function()
        ---@type string[]
        local names = {}
        for _, row in ipairs(rows()) do
          names[#names + 1] = assert(row:match("^(%w+)"))
        end
        eq(names, expected)
        return true
      end,
      "<Esc>",
    })
    require("agents").actions()
    finish()
  end,
})

T["actions picker runs the chosen command in the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("agents").hide(session.id)
  drive({
    function()
      eq(assert(mini.get_picker_opts()).source.name, "Agents: Actions")
      eq(rows()[1], "send   · Pick context to send to a session")
      eq(row_highlights()[1], { "AgentsPickerSeparator", " · " })
      eq(row_highlights()[2], { "AgentsPickerDescription", "Pick context to send to a session" })
      return true
    end,
    "and kill",
    function()
      if not typed("and kill") then
        return false
      end
      eq(#matches(), 1)
      return true
    end,
    "<CR>",
  })
  require("agents").actions()
  finish()
  eq(require("agents.session").get(session.id), nil)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["actions chain into the session picker from the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("agents").hide(session.id)
  drive({
    "^pick",
    function()
      if not typed("^pick") then
        return false
      end
      eq(#matches(), 1)
      return true
    end,
    "<CR>",
    function()
      eq(assert(mini.get_picker_opts()).source.name, "Agents: Sessions")
      eq(assert(mini.get_picker_state()).windows.target, origin)
      return true
    end,
    "<CR>",
  })
  require("agents").actions()
  finish()
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
end

T["context picker closes before sending the selected parts"] = function()
  local origin = vim.api.nvim_get_current_win()
  local parts = { { text = "Explain this" } }
  require("agents.config").get().prompts = { buffer = parts }
  ---@type agents.Part[]?
  local received
  ---@type boolean?
  local closed_before_action
  drive({
    function()
      eq(assert(mini.get_picker_opts()).source.name, "Agents: Send Context")
      eq(rows()[1]:match("^buffer%s+· Saved prompt$") ~= nil, true)
      eq(row_highlights()[2], { "AgentsPickerDescription", "Saved prompt" })
      return true
    end,
    "Copy entire buffer text",
    function()
      if not typed("Copy entire buffer text") then
        return false
      end
      eq(#matches(), 1)
      return true
    end,
    "<C-u>Saved prompt",
    function()
      if not typed("Saved prompt") then
        return false
      end
      eq(#matches(), 1)
      return true
    end,
    "<CR>",
  })
  require("agents.picker").context(require("agents.context").capture(), function(selected)
    received = selected
    closed_before_action = not mini.is_picker_active()
  end)
  finish()
  eq(received, parts)
  eq(closed_before_action, true)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["cancelling, empty matches, and disabled native placement invoke no action"] = function()
  local session = H.new()
  require("agents").hide(session.id)
  local windows = #vim.api.nvim_list_wins()
  drive({ "<Esc>" })
  require("agents").pick()
  finish()
  eq(vim.fn.win_findbuf(session.buf), {})

  drive({
    "no-such-row",
    function()
      if not typed("no-such-row") then
        return false
      end
      eq(matches(), {})
      return true
    end,
    "<CR>",
  })
  require("agents").pick()
  finish()
  eq(vim.fn.win_findbuf(session.buf), {})

  drive({
    "<C-v>",
    function()
      eq(mini.is_picker_active(), true)
      eq(#vim.api.nvim_list_wins(), windows + 1)
      return true
    end,
    "<Esc>",
  })
  require("agents").actions()
  finish()
  eq(#vim.api.nvim_list_wins(), windows)
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(require("agents.session").get(session.id), session)
end

T["marking keys are disabled because menus act on one row"] = function()
  local first, second = H.new(), H.new()
  require("agents").hide(first.id)
  require("agents").hide(second.id)
  drive({
    "<C-n>",
    "<C-x>",
    "<C-a>",
    "<M-CR>",
    "<M-Space>",
    function()
      eq(mini.is_picker_active(), true)
      eq(assert(mini.get_picker_matches()).marked, {})
      eq(#matches(), 2)
      eq(#rows(), 2)
      return true
    end,
    "<Esc>",
  })
  require("agents").pick()
  finish()
  eq(vim.fn.win_findbuf(first.buf), {})
  eq(vim.fn.win_findbuf(second.buf), {})
end

T["duplicate display text resolves to the selected original item once"] = function()
  ---@type string[]
  local chosen = {}
  drive({ "<C-n>", "<CR>" })
  require("agents.picker").open({
    title = "Duplicates",
    items = { { text = "same", data = "first" }, { text = "same", data = "second" } },
    default = "pick",
    actions = {
      ---@param item agents.PickerItem<string>
      pick = function(item)
        chosen[#chosen + 1] = item.data
      end,
    },
  })
  finish()
  eq(chosen, { "second" })
end

T["native info view lists adapter mappings and previews stay disabled"] = function()
  local session = H.new()
  require("agents").hide(session.id)
  drive({
    "<Tab>",
    function()
      eq(assert(mini.get_picker_state()).buffers.preview, nil)
      eq(rows()[1]:sub(1, #"○"), "○")
      return true
    end,
    "<S-Tab>",
    function()
      local lines = info_lines()
      if not lines then
        return false
      end
      eq(vim.list_contains(lines, "Mappings (custom)"), true)
      eq(mapping_key(lines, "Agents open in vsplit"), "<C-v>")
      eq(mapping_key(lines, "Agents open in split"), "<C-s>")
      eq(mapping_key(lines, "Agents open in tabpage"), "<C-t>")
      eq(mapping_key(lines, "Agents open in float"), "<M-f>")
      eq(mapping_key(lines, "Agents open here"), "<C-CR>")
      eq(mapping_key(lines, "Agents hide session"), "<M-h>")
      eq(mapping_key(lines, "Agents close session"), "<C-d>")
      eq(mapping_key(lines, "Agents edit command"), nil)
      eq(mapping_key(lines, "Choose"), "<CR>")
      eq(mapping_key(lines, "Toggle info"), "<S-Tab>")
      eq(mapping_key(lines, "Choose in vsplit"), nil)
      eq(mapping_key(lines, "Choose in split"), nil)
      eq(mapping_key(lines, "Choose in tabpage"), nil)
      eq(mapping_key(lines, "Toggle preview"), nil)
      eq(mapping_key(lines, "Mark"), nil)
      eq(mapping_key(lines, "Mark all"), nil)
      eq(mapping_key(lines, "Choose marked"), nil)
      eq(mapping_key(lines, "Refine marked"), nil)
      eq(mapping_key(lines, "Refine"), "<C-Space>")
      return true
    end,
    "<Esc>",
  })
  require("agents").pick()
  finish()
  eq(vim.fn.win_findbuf(session.buf), {})

  drive({
    "<S-Tab>",
    function()
      local lines = info_lines()
      if not lines then
        return false
      end
      eq(mapping_key(lines, "Agents edit command"), "<C-e>")
      eq(mapping_key(lines, "Agents open in vsplit"), "<C-v>")
      eq(mapping_key(lines, "Agents hide session"), nil)
      eq(mapping_key(lines, "Agents close session"), nil)
      return true
    end,
    "<Esc>",
  })
  require("agents").new()
  finish()
  eq(#require("agents").sessions(), 1)

  drive({
    "<S-Tab>",
    function()
      local lines = info_lines()
      if not lines then
        return false
      end
      eq(vim.list_contains(lines, "Mappings (custom)"), false)
      eq(mapping_key(lines, "Choose"), "<CR>")
      return true
    end,
    "<Esc>",
  })
  require("agents").actions()
  finish()
end

T["configured mini.pick keys take precedence over adapter bindings"] = test.new_set({
  parametrize = { { "global" }, { "buffer" } },
}, {
  ---@param scope string
  ["from global or buffer-local configuration"] = function(scope)
    local session = H.new()
    require("agents").hide(session.id)
    local origin = vim.api.nvim_get_current_win()
    ---@type agents.pickers.MiniMappings
    local overrides = { scroll_down = "<C-d>", choose_in_vsplit = "<C-o>", choose_in_split = "" }
    if scope == "global" then
      mini.config.mappings = vim.tbl_extend("force", mini.config.mappings, overrides)
    else
      vim.b.minipick_config = { mappings = overrides }
    end
    drive({
      "<S-Tab>",
      function()
        local lines = info_lines()
        if not lines then
          return false
        end
        eq(mapping_key(lines, "Scroll down"), "<C-d>")
        eq(mapping_key(lines, "Agents close session"), nil)
        eq(mapping_key(lines, "Agents open in vsplit"), "<C-o>")
        eq(mapping_key(lines, "Agents open in split"), nil)
        eq(mapping_key(lines, "Agents open in tabpage"), "<C-t>")
        return true
      end,
      "<S-Tab>",
      "<C-d>",
      function()
        eq(mini.is_picker_active(), true)
        eq(assert(mini.get_picker_state()).buffers.info == nil, false)
        return true
      end,
      "<C-o>",
    })
    require("agents").pick()
    finish()
    eq(require("agents.session").get(session.id), session)
    eq(vim.api.nvim_get_current_buf(), session.buf)
    eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
    eq(#vim.fn.win_findbuf(session.buf), 1)
  end,
})

T["adapter mapping names leave user custom mappings intact"] = function()
  local ran = false
  mini.config.mappings.open_in_float = {
    char = "<F6>",
    func = function()
      ran = true
    end,
  }
  local session = H.new()
  require("agents").hide(session.id)
  drive({
    "<S-Tab>",
    function()
      local lines = info_lines()
      if not lines then
        return false
      end
      eq(mapping_key(lines, "Open in float"), "<F6>")
      eq(mapping_key(lines, "Agents open in float"), "<M-f>")
      return true
    end,
    "<S-Tab>",
    "<F6>",
    function()
      eq(ran, true)
      eq(mini.is_picker_active(), true)
      return true
    end,
    "<Esc>",
  })
  require("agents").pick()
  finish()
  eq(vim.fn.win_findbuf(session.buf), {})
end

T["marker overrides and Unicode titles keep highlights aligned"] = function()
  require("agents.config").get().icons = { visible = "v", hidden = "h" }
  local session = H.new()
  session.title = "Ünïcödé — títle"
  require("agents").hide(session.id)
  local directory = vim.fn.fnamemodify(session.cwd, ":~")
  drive({
    function()
      eq(rows(), { "h  cat · Ünïcödé — títle · " .. directory })
      eq(row_highlights(), {
        { "AgentsPickerHidden", "h" },
        { "AgentsPickerSeparator", " · " },
        { "AgentsPickerSeparator", " · " },
        { "AgentsPickerDirectory", directory },
      })
      return true
    end,
    "títle",
    function()
      if not typed("títle") then
        return false
      end
      eq(#matches(), 1)
      eq(match_highlights(), { "t", "í", "t", "l", "e" })
      return true
    end,
    "<Esc>",
  })
  require("agents").pick()
  finish()
end

T["a menu requested from a mini.pick action opens afterwards with that picker's target"] = function()
  local session = H.new()
  require("agents").hide(session.id)
  local origin = vim.api.nvim_get_current_win()
  ---@type boolean?
  local deferred
  drive({
    "<F6>",
    function()
      eq(assert(mini.get_picker_opts()).source.name, "Agents: Sessions")
      eq(assert(mini.get_picker_state()).windows.target, origin)
      return true
    end,
    "<CR>",
  })
  ---@type { start: fun(opts: { source: { name: string, items: string[] }, mappings: agents.pickers.MiniMappings }) }
  local raw = require("mini.pick")
  raw.start({
    source = { name = "Probe", items = { "one" } },
    mappings = {
      agents = {
        char = "<F6>",
        func = function()
          -- The menu must wait for this picker instead of interrupting it.
          require("agents").pick()
          deferred = mini.is_picker_active()
          return true
        end,
      },
    },
  })
  H.wait(function()
    return not mini.is_picker_active() and vim.api.nvim_get_current_buf() == session.buf
  end)
  finish()
  eq(deferred, true)
  eq(vim.api.nvim_win_is_valid(origin), true)
  eq(vim.api.nvim_win_get_buf(origin) == session.buf, false)
end

T["sending without focus from a mini.pick action returns to that picker's target"] = function()
  local origin = vim.api.nvim_get_current_win()
  drive({
    "<F6>",
    function()
      eq(assert(mini.get_picker_opts()).source.name, "Agents: New Session")
      return true
    end,
    "<CR>",
  })
  ---@type { start: fun(opts: { source: { name: string, items: string[] }, mappings: agents.pickers.MiniMappings }) }
  local raw = require("mini.pick")
  raw.start({
    source = { name = "Probe", items = { "one" } },
    mappings = {
      agents = {
        char = "<F6>",
        func = function()
          require("agents").send({ { text = "test" } }, { focus = false })
          return true
        end,
      },
    },
  })
  H.wait(function()
    return not mini.is_picker_active() and #require("agents").sessions() == 1
  end)
  finish()
  local session = assert(require("agents").sessions()[1])
  eq(require("agents.window").visible(session), true)
  eq(vim.api.nvim_get_current_win(), origin)
  eq(vim.api.nvim_get_mode().mode, "n")
end

return T
