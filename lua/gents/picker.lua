local M = {}

---@class gents.PickerChunk
---@field text string
---@field kind? gents.PickerChunkKind Styling role for rich picker adapters.

---@alias gents.PickerChunkKind
---| "directory"
---| "visible"
---| "hidden"
---| "placeholder"
---| "separator"
---| "description"
---| "status_working"
---| "status_blocked"
---| "status_done"
---| "status_error"

---@class gents.PickerItem<T>
---@field text string
---@field preview? string
---@field data T
---@field hl? string Suggested highlight group for adapters that support item styling.
---@field chunks? gents.PickerChunk[] Styled parts that concatenate to text.

---@class gents.PickerSpec<T>
---@field title string
---@field items gents.PickerItem<T>[]
---@field actions table<string, fun(item: gents.PickerItem<T>)>
---@field default string Action name used for Enter.
---@field watch? fun(on_change: fun()): fun() Subscribe to in-place item updates; returns a function that stops them.

---@alias gents.PickerAdapter fun<T>(spec: gents.PickerSpec<T>)
---@alias gents.Picker "snacks"|"mini"|"telescope"|"fzf-lua"|gents.PickerAdapter

---Built-in adapter modules by configuration value, loaded when a menu opens.
---@type table<string, string>
local builtin = {
  snacks = "gents.pickers.snacks",
  mini = "gents.pickers.mini",
  telescope = "gents.pickers.telescope",
  ["fzf-lua"] = "gents.pickers.fzf",
}

---Highlight groups for styled chunk kinds, shared by the built-in adapters.
---@type table<string, string>
M.chunk_highlights = {
  directory = "GentsPickerDirectory",
  visible = "GentsPickerVisible",
  hidden = "GentsPickerHidden",
  placeholder = "GentsPickerPlaceholder",
  separator = "GentsPickerSeparator",
  description = "GentsPickerDescription",
  status_working = "GentsPickerWorking",
  status_blocked = "GentsPickerBlocked",
  status_done = "GentsPickerDone",
  status_error = "GentsPickerError",
}

---Define the default picker highlight groups without replacing existing
---definitions. The directory default is a plugin-owned group that follows
---Snacks styling once Snacks has defined its groups, which happens after
---startup, and uses a standard group otherwise.
function M.define_highlights()
  local links = {
    GentsPickerDirectory = "GentsPickerDirectoryDefault",
    GentsPickerVisible = "DiagnosticInfo",
    GentsPickerHidden = "Comment",
    GentsPickerPlaceholder = "Comment",
    GentsPickerSeparator = "Comment",
    GentsPickerDescription = "Comment",
    GentsPickerWorking = "DiagnosticInfo",
    GentsPickerBlocked = "DiagnosticWarn",
    GentsPickerDone = "DiagnosticOk",
    GentsPickerError = "DiagnosticError",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
  vim.api.nvim_set_hl(0, "GentsPickerDirectoryDefault", {
    link = vim.fn.hlexists("SnacksPickerDir") == 1 and "SnacksPickerDir" or "NonText",
  })
end

---The window a menu returns to before running an action. While a mini.pick or
---Telescope picker is active, the window it was opened from is the origin
---rather than the picker window.
---@return integer
function M.origin()
  local adapter = require("gents.config").get().picker
  if adapter == "mini" or adapter == "telescope" then
    ---@type integer?
    local origin = require(builtin[adapter]).origin()
    if origin then
      return origin
    end
  end
  return vim.api.nvim_get_current_win()
end

---@param origin integer
---@param kind string
---@return boolean
local function restore_origin(origin, kind)
  if not vim.api.nvim_win_is_valid(origin) then
    vim.notify(
      "gents.nvim: the window that opened the " .. kind .. " picker no longer exists",
      vim.log.levels.ERROR
    )
    return false
  end
  vim.api.nvim_set_current_win(origin)
  return true
end

---@generic T
---@param spec gents.PickerSpec<T>
function M.open(spec)
  local adapter = require("gents.config").get().picker
  local module = type(adapter) == "string" and builtin[adapter] or nil
  -- Custom adapters may style rows with the same groups as the built-in ones.
  M.define_highlights()
  if module then
    require(module).open(spec)
    return
  elseif adapter then
    adapter(spec)
    return
  end

  vim.ui.select(
    spec.items,
    {
      prompt = spec.title,
      ---@param item { text: string }
      ---@return string
      format_item = function(item)
        return item.text
      end,
    },
    ---@param item? gents.PickerItem<unknown>
    function(item)
      if item then
        spec.actions[spec.default](item)
      end
    end
  )
end

---@generic T
---@param items gents.PickerItem<T>[]
---@param descriptions table<integer, string>
local function describe_items(items, descriptions)
  local width = 0
  for _, item in ipairs(items) do
    width = math.max(width, vim.fn.strdisplaywidth(item.text))
  end
  for index, item in ipairs(items) do
    local description = descriptions[index]
    if description and description ~= "" then
      local label = item.text .. string.rep(" ", width - vim.fn.strdisplaywidth(item.text))
      item.chunks = {
        { text = label },
        { text = " · ", kind = "separator" },
        { text = description, kind = "description" },
      }
      item.text = label .. " · " .. description
    end
  end
end

---@return gents.CommandName[]
local function contextual_commands()
  local registry = require("gents.session")
  local running = false
  for _, session in ipairs(registry.list()) do
    if session.state ~= "exited" then
      running = true
      break
    end
  end
  if not running then
    return { "new", "send" }
  end
  local current = registry.current()
  if current and current.state ~= "exited" then
    return { "focus", "hide", "toggle", "close", "pick", "send", "new" }
  end
  return { "send", "toggle", "focus", "pick", "hide", "close", "new" }
end

---@param callback fun(command: gents.CommandName)
function M.commands(callback)
  local origin = M.origin()
  ---@type gents.PickerItem<gents.CommandName>[]
  local items = {}
  ---@type table<gents.CommandName, string>
  local descriptions = {
    close = "Hide and kill a session",
    focus = "Switch focus between a session and your last buffer",
    hide = "Hide a session without killing it",
    new = "Start a new session",
    pick = "Existing session picker",
    send = "Pick context to send to a session",
    toggle = "Show or hide a session",
  }
  ---@type string[]
  local details = {}
  for _, command in ipairs(contextual_commands()) do
    items[#items + 1] = { text = command, data = command }
    details[#items] = assert(descriptions[command])
  end
  describe_items(items, details)
  M.open({
    title = "Gents: Actions",
    items = items,
    default = "run",
    actions = {
      ---@param item gents.PickerItem<gents.CommandName>
      run = function(item)
        if restore_origin(origin, "actions") then
          callback(item.data)
        end
      end,
    },
  })
end

---@param callback fun(tool: gents.Tool, opts: gents.NewOptions, cwd: string)
---@param opts? gents.NewOptions
function M.tools(callback, opts)
  local config = require("gents.config").get()
  local origin = M.origin()
  local cwd = vim.api.nvim_win_call(origin, function()
    return vim.fn.getcwd(0)
  end)
  ---@type gents.PickerItem<gents.Tool>[]
  local items = {}
  ---@type gents.PickerItem<gents.Tool>[]
  local unavailable = {}
  ---@type table<integer, string>
  local descriptions = {}
  for _, name in ipairs(require("gents.tools").names(config.tools)) do
    local tool = config.tools[name]
    if tool.enabled ~= false then
      local missing = vim.fn.executable(tool.cmd[1]) == 0
      local group = missing and unavailable or items
      group[#group + 1] = {
        text = name,
        data = tool,
        hl = missing and "Comment" or nil,
      }
    end
  end
  for _, item in ipairs(unavailable) do
    items[#items + 1] = item
  end
  for index, item in ipairs(items) do
    local missing = vim.fn.executable(item.data.cmd[1]) == 0
    local unsupported = opts and opts.resume ~= nil and type(item.data.resume) ~= "function"
    descriptions[index] = missing and "Not installed" or ""
    if unsupported then
      descriptions[index] = (missing and "Not installed; " or "") .. "Resume unsupported"
      item.hl = "Comment"
    end
  end
  describe_items(items, descriptions)

  ---@param item gents.PickerItem<gents.Tool>
  ---@param launch_opts gents.NewOptions
  local function launch(item, launch_opts)
    if not restore_origin(origin, "tool") then
      return
    end
    local tool = item.data
    assert(
      launch_opts.resume == nil or type(tool.resume) == "function",
      "gents: tool does not support resume: " .. tool.name
    )
    local cmd = launch_opts.cmd or tool.cmd
    if vim.fn.executable(cmd[1]) == 0 then
      vim.notify("gents.nvim: executable not found: " .. cmd[1], vim.log.levels.ERROR)
      if tool.url then
        vim.ui.open(tool.url)
      end
      return
    end
    callback(tool, launch_opts, cwd)
  end

  ---@type gents.PickerSpec<gents.Tool>
  local spec = {
    title = "Gents: New Session",
    items = items,
    default = "new",
    actions = {
      ---@param item gents.PickerItem<gents.Tool>
      new = function(item)
        launch(item, vim.deepcopy(opts or {}))
      end,
      ---@param item gents.PickerItem<gents.Tool>
      edit_args = function(item)
        if not restore_origin(origin, "tool") then
          return
        end
        local launch_opts = vim.deepcopy(opts or {})
        local cmd = require("gents.tools").command(item.data, launch_opts, cwd)
        vim.ui.input(
          { prompt = "Gents: command: ", default = table.concat(cmd, " ") .. " " },
          function(value)
            if value == nil then
              return
            end
            ---@type string[]
            local edited = {}
            for word in value:gmatch("%S+") do
              edited[#edited + 1] = word
            end
            if #edited == 0 then
              vim.notify("gents.nvim: command must not be empty", vim.log.levels.ERROR)
              return
            end
            launch_opts.cmd, launch_opts.args, launch_opts.resume = edited, nil, nil
            launch(item, launch_opts)
          end
        )
      end,
    },
  }
  for _, layout in ipairs({ "vsplit", "split", "tabnew", "float", "current" }) do
    ---@param item gents.PickerItem<gents.Tool>
    spec.actions[layout] = function(item)
      local launch_opts = vim.deepcopy(opts or {})
      launch_opts.layout = layout
      launch(item, launch_opts)
    end
  end
  M.open(spec)
end

---@param title string
---@return string
local function display_title(title)
  if vim.fn.strdisplaywidth(title) <= 60 then
    return title
  end
  local length = 57
  local shortened = vim.fn.strcharpart(title, 0, length, true)
  while vim.fn.strdisplaywidth(shortened) > 57 do
    length = length - 1
    shortened = vim.fn.strcharpart(title, 0, length, true)
  end
  return shortened .. "..."
end

---@param icons gents.Icons
---@return integer Display cells reserved for every status glyph.
local function status_width(icons)
  local width = 0
  for _, icon in ipairs({
    icons.idle,
    icons.working,
    icons.blocked,
    icons.question,
    icons.permission or icons.blocked,
    icons.auth or icons.blocked,
    icons.done,
    icons.error,
  }) do
    width = math.max(width, vim.fn.strdisplaywidth(icon))
  end
  return width
end

---The status glyph that replaces the separator between a session's name and
---title. Idle sessions and sessions without native status keep the separator.
---@param session gents.Session
---@param icons gents.Icons
---@param width integer
---@return gents.PickerChunk
local function status_chunk(session, icons, width)
  local status = require("gents.terminal_status").display(session)
  ---@type string, gents.PickerChunkKind
  local glyph, kind = icons.idle, "separator"
  if status and status.state == "blocked" then
    kind = "status_blocked"
    if status.kind == "question" then
      glyph = icons.question
    elseif status.kind == "permission" then
      glyph = icons.permission or icons.blocked
    elseif status.kind == "auth" then
      glyph = icons.auth or icons.blocked
    else
      glyph = icons.blocked
    end
  elseif status and status.state == "working" then
    glyph, kind = icons.working, "status_working"
  elseif status and status.state == "done" then
    glyph, kind = icons.done, "status_done"
  elseif status and status.state == "error" then
    glyph, kind = icons.error, "status_error"
  end
  local padding = string.rep(" ", width - vim.fn.strdisplaywidth(glyph))
  return { text = " " .. glyph .. padding .. " ", kind = kind }
end

---@param chunks gents.PickerChunk[]
---@return string
local function chunk_text(chunks)
  ---@type string[]
  local parts = {}
  for _, chunk in ipairs(chunks) do
    parts[#parts + 1] = chunk.text
  end
  return table.concat(parts)
end

---@param candidates gents.Session[]
---@param callback fun(session: gents.Session)
---@param on_place? fun(session: gents.Session, layout: gents.Layout)
function M.sessions(candidates, callback, on_place)
  local window = require("gents.window")
  local tab = vim.api.nvim_get_current_tabpage()
  local origin = M.origin()
  ---@type gents.Session[]
  local ordered = {}
  ---@type table<integer, integer>
  local ranks = {}
  for _, session in ipairs(candidates) do
    ordered[#ordered + 1] = session
    -- A native view elsewhere takes precedence over the last plugin-managed tab.
    local hidden_here = session.tab == tab and #vim.fn.win_findbuf(session.buf) == 0
    ranks[session.id] = window.visible(session, tab) and 1 or (hidden_here and 2 or 3)
  end
  table.sort(ordered, function(a, b)
    if ranks[a.id] ~= ranks[b.id] then
      return ranks[a.id] < ranks[b.id]
    end
    return a.id < b.id
  end)

  ---@type gents.PickerItem<gents.Session>[]
  local items = {}
  ---@type { session: gents.Session, marker: string, visible: boolean, label: string, title: string }[]
  local rows = {}
  local marker_width, label_width, title_width = 0, 0, 0
  local icons = require("gents.config").get().icons
  local glyph_width = status_width(icons)
  for _, session in ipairs(ordered) do
    local visible = window.visible(session, tab)
    local marker = visible and icons.visible or icons.hidden
    local label = session.title and session.tool.name or session.label
    local title = session.title and display_title(session.title) or "Untitled"
    if session.state == "exited" then
      title = title .. "  [exited]"
    end
    rows[#rows + 1] = {
      session = session,
      marker = marker,
      visible = visible,
      label = label,
      title = title,
    }
    marker_width = math.max(marker_width, vim.fn.strdisplaywidth(marker))
    label_width = math.max(label_width, vim.fn.strdisplaywidth(label))
    title_width = math.max(title_width, vim.fn.strdisplaywidth(title))
  end

  ---@type table<integer, gents.PickerItem<gents.Session>>
  local by_id = {}
  for _, row in ipairs(rows) do
    local session = row.session
    local summary = string.rep(" ", marker_width - vim.fn.strdisplaywidth(row.marker) + 2)
      .. row.label
      .. string.rep(" ", label_width - vim.fn.strdisplaywidth(row.label))
    local padding = string.rep(" ", title_width - vim.fn.strdisplaywidth(row.title))
    local directory = vim.fn.fnamemodify(session.cwd, ":~")
    ---@type gents.PickerChunk[]
    local chunks = {
      { text = row.marker, kind = row.visible and "visible" or "hidden" },
      { text = summary },
      status_chunk(session, icons, glyph_width),
      { text = row.title, kind = not session.title and "placeholder" or nil },
      { text = padding },
      { text = " · ", kind = "separator" },
      { text = directory, kind = "directory" },
    }
    if not vim.deep_equal(session.cmd, session.tool.cmd) then
      chunks[#chunks + 1] = { text = "  " .. table.concat(session.cmd, " ") }
    end
    items[#items + 1] = { text = chunk_text(chunks), data = session, chunks = chunks }
    by_id[session.id] = items[#items]
  end

  ---@param item gents.PickerItem<gents.Session>
  ---@param action fun(session: gents.Session)
  local function select(item, action)
    local session = require("gents.session").get(item.data.id)
    if session and restore_origin(origin, "session") then
      action(session)
    end
  end

  ---@type gents.PickerSpec<gents.Session>
  local spec = {
    title = "Gents: Sessions",
    items = items,
    default = "show",
    actions = {
      ---@param item gents.PickerItem<gents.Session>
      show = function(item)
        select(item, callback)
      end,
      ---@param item gents.PickerItem<gents.Session>
      hide = function(item)
        select(item, function(session)
          window.hide(session, tab)
        end)
      end,
      ---@param item gents.PickerItem<gents.Session>
      close = function(item)
        select(item, require("gents.session").close)
      end,
    },
  }
  for _, layout in ipairs({ "vsplit", "split", "tabnew", "float", "current" }) do
    ---@param item gents.PickerItem<gents.Session>
    spec.actions[layout] = function(item)
      select(item, function(session)
        (on_place or window.show)(session, layout)
      end)
    end
  end

  -- Only status glyphs change in place; rows keep their order and identity.
  spec.watch = function(on_change)
    local scheduled, stopped = false, false
    -- Each watcher compares with what it last drew, since another watcher on
    -- the same spec may already have updated the shared chunks.
    ---@type table<integer, gents.PickerChunk>
    local drawn = {}
    for id, item in pairs(by_id) do
      drawn[id] = item.chunks and item.chunks[3]
    end
    local autocmd = vim.api.nvim_create_autocmd("User", {
      pattern = "GentsStatusChanged",
      desc = "Update session picker status glyphs",
      callback = function(ev)
        ---@type gents.StatusChangedEvent
        local data = ev.data
        local item = by_id[data.id]
        local chunks = item and item.chunks
        if not item or not chunks then
          return
        end
        local chunk = status_chunk(item.data, icons, glyph_width)
        if vim.deep_equal(drawn[data.id], chunk) then
          return
        end
        drawn[data.id] = chunk
        chunks[3] = chunk
        item.text = chunk_text(chunks)
        if not scheduled then
          scheduled = true
          -- One redraw covers every report from the same PTY read.
          vim.schedule(function()
            scheduled = false
            if not stopped then
              on_change()
            end
          end)
        end
      end,
    })
    return function()
      if not stopped then
        stopped = true
        vim.api.nvim_del_autocmd(autocmd)
      end
    end
  end
  M.open(spec)
end

---@param ctx gents.Context
---@param callback fun(parts: gents.Part[])
function M.context(ctx, callback)
  local origin = M.origin()
  local render = require("gents.render")
  local providers = require("gents.providers")
  ---@type gents.PickerItem<gents.Part[]>[]
  local items = {}
  ---@type string[]
  local descriptions = {}

  ---@param label string
  ---@param description string
  ---@param source gents.Item[]
  local function add(label, description, source)
    local parts = render.resolve(source, ctx)
    if parts then
      items[#items + 1] = { text = label, preview = render.text(parts, ctx), data = parts }
      descriptions[#items] = description
    end
  end

  local prompts = require("gents.config").get().prompts
  ---@type string[]
  local names = vim.tbl_keys(prompts)
  table.sort(names)
  for _, name in ipairs(names) do
    add(name, "Saved prompt", prompts[name])
  end
  for _, name in ipairs(providers.names()) do
    add(name, assert(providers.get(name)).desc, { name })
  end
  describe_items(items, descriptions)

  M.open({
    title = "Gents: Send Context",
    items = items,
    default = "send",
    actions = {
      ---@param item gents.PickerItem<gents.Part[]>
      send = function(item)
        if restore_origin(origin, "context") then
          callback(item.data)
        end
      end,
    },
  })
end

return M
