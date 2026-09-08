local test = require("mini.test")
local T = test.new_set()
local fzf_bin = vim.env.FZF_BIN or "fzf"
if not vim.env.FZF_LUA_DIR or vim.fn.executable(fzf_bin) == 0 then
  return T
end

-- The optional integration uses this small surface of the real fzf-lua API.
---@class agents.test.FzfWin
---@field fzf_bufnr? integer
---@field fzf_winid? integer
---@field toggle_help fun(self: agents.test.FzfWin)
---@field close fun(self: agents.test.FzfWin)

---@class agents.test.FzfLua
---@field setup fun(opts: table)
---@field fzf_exec fun(contents: string[], opts: agents.pickers.FzfOptions)

---@class agents.test.FzfUtils
---@field fzf_winobj fun(): agents.test.FzfWin?
---@field ansi_from_hl fun(group: string, text: string): string

vim.opt.runtimepath:append(vim.env.FZF_LUA_DIR)
---@type agents.test.FzfLua
local fzf = require("fzf-lua")
---@type agents.test.FzfUtils
local utils = require("fzf-lua.utils")
fzf.setup({ fzf_bin = fzf_bin })

local H = require("tests.helpers")
local eq = test.expect.equality
local original_input = vim.ui.input
local original_columns = vim.o.columns

T = test.new_set({
  hooks = {
    pre_once = function()
      -- Wide enough for the default 80% float to show complete rows.
      vim.o.columns = 160
    end,
    post_once = function()
      vim.o.columns = original_columns
    end,
    pre_case = function()
      H.reset()
      require("agents").setup({ picker = "fzf-lua" })
      require("agents.config").get().tools = {
        cat = { name = "cat", cmd = { "cat" } },
      }
    end,
    post_case = function()
      -- fzf-lua's default profile hides a finished picker and keeps its process.
      local win = utils.fzf_winobj()
      if win then
        pcall(win.close, win)
      end
      H.wait(function()
        return utils.fzf_winobj() == nil
      end)
      vim.ui.input = original_input
      fzf.setup({ fzf_bin = fzf_bin })
      H.reset()
    end,
  },
})

---@param win agents.test.FzfWin
---@return boolean Whether the picker window is on screen.
local function visible(win)
  return win.fzf_winid ~= nil and vim.api.nvim_win_is_valid(win.fzf_winid)
end

---@param win agents.test.FzfWin
---@return string[] Rendered terminal lines without trailing blanks, top to bottom.
local function screen(win)
  ---@type string[]
  local lines = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(assert(win.fzf_bufnr), 0, -1, false)) do
    local trimmed = line:gsub("%s+$", "")
    if trimmed ~= "" then
      lines[#lines + 1] = trimmed
    end
  end
  return lines
end

---@param win agents.test.FzfWin
---@param text string
---@return boolean
local function shown(win, text)
  for _, line in ipairs(screen(win)) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end

---Wait for a visible fzf window that renders a row containing the text.
---@param text string
---@return agents.test.FzfWin
local function current_picker(text)
  ---@type agents.test.FzfWin?
  local win
  H.wait(function()
    win = utils.fzf_winobj()
    return win ~= nil
      and visible(win)
      and win.fzf_bufnr ~= nil
      and vim.api.nvim_buf_is_valid(win.fzf_bufnr)
      and shown(win, text)
  end)
  return assert(win)
end

---@param win agents.test.FzfWin
---@param keys string Raw terminal input.
local function send(win, keys)
  vim.api.nvim_chan_send(vim.bo[assert(win.fzf_bufnr)].channel, keys)
end

---Send keys that end the picker; fzf-lua hides its window before the action.
---@param win agents.test.FzfWin
---@param keys string
local function press(win, keys)
  local winid = assert(win.fzf_winid)
  send(win, keys)
  H.wait(function()
    return not vim.api.nvim_win_is_valid(winid)
  end)
end

---Type a query and wait for fzf's inline match counter.
---@param win agents.test.FzfWin
---@param query string
---@param count integer
local function filter(win, query, count)
  send(win, query)
  H.wait(function()
    return shown(win, " " .. count .. "/")
  end)
end

---@param win agents.test.FzfWin
---@return string The rendered help window text.
local function help_text(win)
  win:toggle_help()
  ---@type string?
  local text
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf):find("_FzfLuaHelp", 1, true) then
      text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  win:toggle_help()
  return assert(text)
end

---@param callback fun(opts: vim.ui.input.Opts?, on_confirm: fun(input?: string))
local function set_input(callback)
  vim.ui.input = callback
end

---@param group string
---@param text string
---@return string
local function ansi(group, text)
  return utils.ansi_from_hl(group, text)
end

T["rows carry hidden indexes, styled chunks, and help descriptions"] = function()
  local session = H.new({ label = "review" })
  session.title = "Investigate flaky tests"
  require("agents").hide(session.id)
  ---@type { contents: string[], opts: agents.pickers.FzfOptions }?
  local captured
  ---@type function?
  local original = rawget(fzf, "fzf_exec")
  test.finally(function()
    rawset(fzf, "fzf_exec", original)
  end)
  rawset(fzf, "fzf_exec", function(contents, opts)
    captured = { contents = contents, opts = opts }
  end)
  require("agents").pick()
  assert(captured)
  local directory = vim.fn.fnamemodify(session.cwd, ":~")
  eq(captured.contents, {
    "1\t"
      .. ansi("AgentsPickerHidden", "○")
      .. "  cat"
      .. ansi("AgentsPickerSeparator", " · ")
      .. "Investigate flaky tests"
      .. ansi("AgentsPickerSeparator", " · ")
      .. ansi("AgentsPickerDirectory", directory),
  })
  local opts = captured.opts
  eq(opts.winopts.title, " Agents: Sessions ")
  eq(opts.previewer, false)
  eq(opts.fzf_opts["--with-nth"], "2..")
  eq(opts.fzf_opts["--delimiter"], "\t")
  eq(opts.fzf_opts["--ansi"], true)
  eq(opts.fzf_opts["--no-multi"], true)
  -- Inherited options that would break the hidden index or show a preview are reset.
  eq(opts.fzf_opts["--nth"], false)
  eq(opts.fzf_opts["--accept-nth"], false)
  eq(opts.fzf_opts["--preview"], false)
  eq(opts.fzf_opts["--preview-window"], "hidden:right:0")
  ---@type table<string, string>
  local descs = {}
  for key, action in pairs(opts.actions) do
    descs[key] = action.desc
  end
  eq(descs, {
    enter = "agents-show",
    ["ctrl-v"] = "agents-open-in-vsplit",
    ["ctrl-s"] = "agents-open-in-split",
    ["ctrl-t"] = "agents-open-in-tab",
    ["alt-f"] = "agents-open-in-float",
    ["alt-enter"] = "agents-open-here",
    ["alt-h"] = "agents-hide-session",
    ["ctrl-x"] = "agents-close-session",
  })
  -- Selections map back through the hidden index only.
  opts.actions.enter.fn({})
  opts.actions.enter.fn({ "7\tno such row" })
  eq(vim.fn.win_findbuf(session.buf), {})
  opts.actions.enter.fn({ "1\t" .. session.label })
  eq(vim.api.nvim_get_current_buf(), session.buf)
end

T["shows other-tab sessions as hidden with their titles and preserves selection"] = function()
  local session = H.new({ label = "review" })
  session.title = "Investigate flaky tests"
  local session_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  require("agents").pick()
  local directory = vim.fn.fnamemodify(session.cwd, ":~")
  local text = "○  cat · Investigate flaky tests · " .. directory
  local win = current_picker(text)
  eq(shown(win, "1\t"), false)
  filter(win, "no-such-session-or-directory", 0)
  eq(shown(win, text), false)
  send(win, "\21")
  filter(win, "flaky", 1)
  eq(shown(win, text), true)
  press(win, "\r")
  eq(require("agents").current(), session)
  eq(session.label, "review")
  eq(vim.api.nvim_get_current_tabpage(), session_tab)
end

T["explicit placement"] = test.new_set({
  parametrize = { { "\27\r", "current" }, { "\27f", "float" } },
}, {
  ---@param keys string
  ---@param layout string
  ["uses the invoking tab and preserves the session view in another tab"] = function(keys, layout)
    local session = H.new()
    local win = vim.api.nvim_get_current_win()
    vim.cmd.tabnew()
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("agents").pick()
    press(current_picker("Untitled"), keys)
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
    { "\r", "botright vsplit" },
    { "\22", "vsplit" },
    { "\19", "split" },
    { "\20", "tabnew" },
    { "\27f", "float" },
    { "\27\r", "current" },
    { "\27e", "botright vsplit" },
  },
}, {
  ---@param keys string
  ---@param layout string
  ["launch a real session"] = function(keys, layout)
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
    require("agents").new()
    press(current_picker("cat"), keys)
    local session = assert(require("agents").current())
    eq(vim.api.nvim_get_current_win() == origin, layout == "current")
    eq(vim.api.nvim_get_current_tabpage() == tab, layout ~= "tabnew")
    eq(session.cmd, keys == "\27e" and { "cat", "-u" } or { "cat" })
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
    { "\r", "botright vsplit" },
    { "\22", "vsplit" },
    { "\19", "split" },
    { "\20", "tabnew" },
    { "\27f", "float" },
    { "\27\r", "current" },
    { "\27h", "hide" },
    { "\24", "close" },
  },
}, {
  ---@param keys string
  ---@param action string
  ["show hide or close a real session"] = function(keys, action)
    local session = H.new()
    if action ~= "hide" then
      require("agents").hide(session.id)
    end
    local origin, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    require("agents").pick()
    local win = current_picker("Untitled")
    if action == "hide" then
      eq(shown(win, "●  " .. session.label .. " · Untitled · "), true)
    end
    press(win, keys)
    if action == "close" then
      eq(require("agents.session").get(session.id), nil)
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
  ["preserves context order in the fzf list"] = function(context, expected)
    if context ~= "empty" then
      local session = H.new()
      if context == "editor" then
        require("agents").hide(session.id)
      end
    end
    require("agents").actions()
    local win = current_picker("Start a new session")
    ---@type string[]
    local names = {}
    for _, line in ipairs(screen(win)) do
      local name = line:match("(%w+)%s+· ")
      if name then
        names[#names + 1] = name
      end
    end
    eq(names, expected)
    press(win, "\27")
  end,
})

T["actions picker runs the chosen command in the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").actions()
  local win = current_picker("send   · Pick context to send to a session")
  filter(win, "and kill", 1)
  press(win, "\r")
  eq(require("agents.session").get(session.id), nil)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["actions chain into the session picker from the invoking window"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").actions()
  local win = current_picker("Existing session picker")
  filter(win, "Existing session", 1)
  press(win, "\r")
  local sessions = current_picker("Untitled")
  eq(sessions ~= win, true)
  press(sessions, "\r")
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
  ---@type agents.test.FzfWin?
  local win
  require("agents.picker").context(require("agents.context").capture(), function(selected)
    received = selected
    closed_before_action = win ~= nil and not visible(win)
  end)
  win = current_picker("Saved prompt")
  filter(win, "Copy entire buffer text", 1)
  send(win, "\21")
  filter(win, "Saved prompt", 1)
  press(win, "\r")
  eq(received, parts)
  eq(closed_before_action, true)
  eq(vim.api.nvim_get_current_win(), origin)
end

T["cancelling, empty matches, and unbound placement keys invoke no action"] = function()
  local session = H.new()
  require("agents").hide(session.id)

  require("agents").pick()
  press(current_picker("Untitled"), "\27")
  eq(vim.fn.win_findbuf(session.buf), {})

  require("agents").pick()
  local win = current_picker("Untitled")
  filter(win, "no-such-row", 0)
  press(win, "\r")
  eq(vim.fn.win_findbuf(session.buf), {})

  require("agents").actions()
  win = current_picker("Start a new session")
  send(win, "\22")
  vim.wait(200)
  eq(utils.fzf_winobj(), win)
  eq(visible(win), true)
  eq(shown(win, "Start a new session"), true)
  press(win, "\27")
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(require("agents.session").get(session.id), session)
end

T["duplicate display text resolves to the selected original item once"] = function()
  ---@type string[]
  local chosen = {}
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
  press(current_picker("same"), "\14\r")
  eq(chosen, { "second" })
end

T["native help lists adapter actions by name"] = function()
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").pick()
  local win = current_picker("Untitled")
  local help = help_text(win)
  for _, entry in ipairs({
    { "enter", "agents-show" },
    { "ctrl-v", "agents-open-in-vsplit" },
    { "ctrl-s", "agents-open-in-split" },
    { "ctrl-t", "agents-open-in-tab" },
    { "alt-f", "agents-open-in-float" },
    { "alt-enter", "agents-open-here" },
    { "alt-h", "agents-hide-session" },
    { "ctrl-x", "agents-close-session" },
  }) do
    eq(help:find("|" .. entry[1] .. "|", 1, true) ~= nil, true)
    eq(help:find("*" .. entry[2] .. "*", 1, true) ~= nil, true)
  end
  eq(help:find("agents-edit-command", 1, true), nil)
  eq(help:find("|f1|", 1, true) ~= nil, true)
  press(win, "\27")

  require("agents").new()
  win = current_picker("cat")
  help = help_text(win)
  eq(help:find("*agents-start*", 1, true) ~= nil, true)
  eq(help:find("*agents-edit-command*", 1, true) ~= nil, true)
  eq(help:find("agents-hide-session", 1, true), nil)
  press(win, "\27")
end

T["configured fzf-lua keymaps take precedence over adapter bindings"] = test.new_set({
  parametrize = { { "bound" }, { "disabled" } },
}, {
  ---@param state string
  ["whether bound or disabled"] = function(state)
    local bound = state == "bound"
    fzf.setup({
      fzf_bin = fzf_bin,
      keymap = {
        fzf = { ["ctrl-x"] = bound and "toggle" or false, ["ctrl-u"] = "unix-line-discard" },
        builtin = { ["<F1>"] = "toggle-help", ["<M-h>"] = bound and "toggle-fullscreen" or false },
      },
    })
    local session = H.new()
    require("agents").hide(session.id)
    require("agents").pick()
    local win = current_picker("Untitled")
    local help = help_text(win)
    eq(help:find("agents-close-session", 1, true), nil)
    eq(help:find("agents-hide-session", 1, true), nil)
    eq(help:find("*agents-open-in-vsplit*", 1, true) ~= nil, true)
    send(win, "\24")
    send(win, "\27h")
    vim.wait(200)
    eq(utils.fzf_winobj(), win)
    eq(visible(win), true)
    eq(require("agents.session").get(session.id), session)
    eq(vim.fn.win_findbuf(session.buf), {})
    press(win, "\22")
    eq(vim.api.nvim_get_current_buf(), session.buf)
  end,
})

T["an uppercase Alt fzf keymap leaves the lowercase adapter key bound"] = function()
  fzf.setup({ fzf_bin = fzf_bin, keymap = { fzf = { ["alt-F"] = "first" } } })
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").pick()
  local win = current_picker("Untitled")
  local help = help_text(win)
  eq(help:find("|alt-F|", 1, true) ~= nil, true)
  eq(help:find("*agents-open-in-float*", 1, true) ~= nil, true)
  press(win, "\27f")
  eq(vim.api.nvim_get_current_buf(), session.buf)
  eq(vim.api.nvim_win_get_config(0).relative, "editor")
end

T["inherited fzf options do not break selection or show a preview"] = function()
  fzf.setup({
    fzf_bin = fzf_bin,
    fzf_opts = { ["--accept-nth"] = "2..", ["--nth"] = "1", ["--preview"] = "echo PREVIEWPANE" },
  })
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").pick()
  local win = current_picker("Untitled")
  vim.wait(200)
  eq(shown(win, "PREVIEWPANE"), false)
  press(win, "\r")
  eq(vim.api.nvim_get_current_buf(), session.buf)
end

T["a missing configured binary falls back to fzf on PATH like fzf-lua"] = function()
  local path = assert(os.getenv("PATH"))
  test.finally(function()
    vim.fn.setenv("PATH", path)
  end)
  vim.fn.setenv("PATH", vim.fn.fnamemodify(vim.fn.exepath(fzf_bin), ":h") .. ":" .. path)
  fzf.setup({ fzf_bin = vim.fn.tempname() })
  local adapter = require("agents.pickers.fzf")
  eq(adapter.binary(assert(adapter.instance())), "fzf")
  local session = H.new()
  require("agents").hide(session.id)
  require("agents").pick()
  press(current_picker("Untitled"), "\r")
  eq(vim.api.nvim_get_current_buf(), session.buf)
end

return T
