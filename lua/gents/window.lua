local M = {}

---@param session gents.Session
function M.attach(session)
  local terminal_input = false
  local restoring_input = false
  vim.api.nvim_create_autocmd("TermEnter", {
    buffer = session.buf,
    desc = "Remember session terminal input mode",
    callback = function()
      terminal_input = true
      restoring_input = false
    end,
  })
  vim.api.nvim_create_autocmd("TermLeave", {
    buffer = session.buf,
    desc = "Remember deliberate exits from session terminal input",
    callback = function()
      local win = vim.api.nvim_get_current_win()
      -- Navigation mappings can leave terminal mode before switching windows.
      vim.schedule(function()
        if
          vim.api.nvim_get_current_win() == win and require("gents.session").current() == session
        then
          terminal_input = vim.fn.mode() == "t"
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    buffer = session.buf,
    desc = "Restore session terminal input on reentry",
    callback = function()
      ---@type string
      local mode = vim.fn.mode():sub(1, 1)
      if
        terminal_input
        and session.state ~= "exited"
        and require("gents.session").current() == session
        and mode ~= "t"
        and mode ~= "i"
        and mode ~= "R"
      then
        restoring_input = true
        vim.cmd.startinsert()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    buffer = session.buf,
    desc = "Cancel session input restoration when leaving before it starts",
    callback = function()
      if restoring_input then
        -- Opening a hidden session for send can immediately return to the editor.
        vim.cmd.stopinsert()
        restoring_input = false
      end
    end,
  })
end

---@param session gents.Session
---@param tab? integer Defaults to the current tab.
---@return integer?
function M.find(session, tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.fn.win_findbuf(session.buf)) do
    if vim.api.nvim_win_get_tabpage(win) == tab then
      return win
    end
  end
end

---@param session gents.Session
---@param tab? integer Defaults to the current tab.
---@return boolean
function M.visible(session, tab)
  return M.find(session, tab) ~= nil
end

---@param value gents.FloatValue
---@param field string
---@return number
local function float_value(value, field)
  ---@type number
  local resolved
  if type(value) == "function" then
    resolved = value()
  else
    resolved = value
  end
  assert(
    type(resolved) == "number" and resolved == resolved and math.abs(resolved) < math.huge,
    "gents: float " .. field .. " must resolve to a finite number"
  )
  return resolved
end

---@param value gents.FloatValue
---@param size integer
---@param dimension "width"|"height"
---@return integer
local function float_dimension(value, size, dimension)
  local resolved = float_value(value, dimension)
  if resolved > 0 and resolved <= 1 then
    resolved = size * resolved
  end
  return math.max(1, math.floor(resolved))
end

---@param layout gents.FloatConfig
---@return vim.api.keyset.win_config
local function float_config(layout)
  -- Geometry resolution leaves nested window options untouched.
  ---@type gents.FloatOptions
  local opts = vim.tbl_extend("force", layout, {})
  opts.width = float_dimension(layout.width, vim.o.columns, "width")
  opts.height = float_dimension(layout.height, vim.o.lines, "height")
  opts.relative = opts.relative or "editor"
  opts.row = opts.row ~= nil and float_value(opts.row, "row")
    or math.floor((vim.o.lines - opts.height) / 2)
  opts.col = opts.col ~= nil and float_value(opts.col, "col")
    or math.floor((vim.o.columns - opts.width) / 2)
  return opts
end

---@class gents.FloatView
---@field layout gents.FloatConfig
---@field relative string
---@field win? integer
---@field bufpos? [integer, integer]
---@field row_offset number
---@field col_offset number

---@type table<integer, gents.FloatView>
local floats = {}
local float_group = vim.api.nvim_create_augroup("GentsFloats", { clear = true })

vim.api.nvim_create_autocmd("WinClosed", {
  group = float_group,
  desc = "Forget closed session floats",
  callback = function(event)
    floats[vim.fn.str2nr(event.match)] = nil
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  group = float_group,
  desc = "Update session float geometry",
  callback = function()
    for win, view in pairs(floats) do
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative == "" then
        floats[win] = nil
      else
        local ok, err = pcall(function()
          local opts = float_config(view.layout)
          ---@type vim.api.keyset.win_config
          local geometry = {
            width = opts.width,
            height = opts.height,
          }
          -- Keep the native anchor resolved at opening (including cursor-relative floats).
          -- If its reference window closed, resize without changing Neovim's remaining anchor.
          if not view.win or vim.api.nvim_win_is_valid(view.win) then
            geometry.relative = view.relative
            geometry.win = view.win
            geometry.bufpos = view.bufpos
            geometry.row = opts.row + view.row_offset
            geometry.col = opts.col + view.col_offset
          end
          vim.api.nvim_win_set_config(win, geometry)
        end)
        if not ok and vim.api.nvim_win_is_valid(win) then
          vim.notify("gents: could not resize float: " .. tostring(err), vim.log.levels.ERROR)
        end
      end
    end
  end,
})

---@param buf? integer Existing buffer; omit to choose a new session's window first.
---@param layout? gents.Layout
---@return integer
function M.open(buf, layout)
  local config = require("gents.config").get()
  layout = layout or config.layout
  if layout == "float" then
    layout = config.float
  end

  ---@type integer
  local win
  if type(layout) == "table" then
    local spec = vim.deepcopy(layout)
    local opts = float_config(spec)
    win = vim.api.nvim_open_win(buf or 0, true, opts)
    local actual = vim.api.nvim_win_get_config(win)
    floats[win] = {
      layout = spec,
      relative = actual.relative,
      win = actual.win,
      bufpos = actual.bufpos,
      row_offset = actual.row - opts.row,
      col_offset = actual.col - opts.col,
    }
  elseif type(layout) == "function" then
    win = layout()
  else
    if layout ~= "current" then
      vim.cmd(layout)
    end
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(win)
  if buf then
    vim.api.nvim_win_set_buf(win, buf)
    local session = require("gents.session").get(vim.b[buf].gents_session)
    if session then
      session.last_float = vim.api.nvim_win_get_config(win).relative ~= ""
    end
  end
  return win
end

---@param session gents.Session
---@param layout? gents.Layout
---@return gents.Session
function M.show(session, layout)
  local wins = vim.fn.win_findbuf(session.buf)
  ---@type integer?
  local opened
  if layout ~= nil or #wins == 0 then
    local win = M.open(session.buf, layout)
    if not vim.list_contains(wins, win) then
      opened = win
    end
  elseif vim.api.nvim_get_current_buf() ~= session.buf then
    vim.api.nvim_set_current_win(wins[1])
  end
  session.tab = vim.api.nvim_get_current_tabpage()
  if session.state ~= "exited" then
    vim.cmd.startinsert()
  end
  if opened then
    require("gents.events").emit("GentsSessionShow", { id = session.id, win = opened })
  end
  return session
end

---@param session gents.Session
---@param tab? integer Restrict hiding to this tab; otherwise hide every view.
---@return gents.Session
function M.hide(session, tab)
  local wins = vim.fn.win_findbuf(session.buf)
  if tab then
    wins = vim.tbl_filter(
      ---@param win integer
      ---@return boolean
      function(win)
        return vim.api.nvim_win_get_tabpage(win) == tab
      end,
      wins
    )
  end
  for _, win in ipairs(wins) do
    local ok, err = pcall(vim.api.nvim_win_hide, win)
    if not ok then
      -- Neovim must keep one non-floating window in the last tab.
      if not tostring(err):match("E444:") and not tostring(err):match("E5601:") then
        error(err, 0)
      end
      local alternate = vim.api.nvim_win_call(win, function()
        return vim.fn.bufnr("#")
      end)
      -- Do not reopen another session or reload an old term:// name after a rename.
      -- Closing sessions keep their buffer marker until their job exits.
      if
        alternate == session.buf
        or not vim.api.nvim_buf_is_loaded(alternate)
        or vim.b[alternate].gents_session ~= nil
      then
        alternate = vim.api.nvim_create_buf(true, false)
      end
      vim.api.nvim_win_set_buf(win, alternate)
    end
  end
  if #wins > 0 and session.job and session.job > 0 and #vim.fn.win_findbuf(session.buf) == 0 then
    require("gents.events").emit("GentsSessionHide", { id = session.id })
  end
  return session
end

return M
