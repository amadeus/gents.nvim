local M = {}

---@param session agents.Session
---@param tab? integer
---@return boolean
function M.visible(session, tab)
  for _, win in ipairs(vim.fn.win_findbuf(session.buf)) do
    if not tab or vim.api.nvim_win_get_tabpage(win) == tab then
      return true
    end
  end
  return false
end

---@param value number
---@param size integer
---@param dimension "width"|"height"
---@return number
local function float_dimension(value, size, dimension)
  assert(type(value) == "number", "agents: float " .. dimension .. " must be a number")
  if value > 0 and value <= 1 then
    return math.floor(size * value)
  end
  return value
end

---@param layout agents.FloatConfig
---@return vim.api.keyset.win_config
local function float_config(layout)
  local opts = vim.deepcopy(layout)
  opts.width = float_dimension(opts.width, vim.o.columns, "width")
  opts.height = float_dimension(opts.height, vim.o.lines, "height")
  opts.relative = opts.relative or "editor"
  opts.row = opts.row or math.floor((vim.o.lines - opts.height) / 2)
  opts.col = opts.col or math.floor((vim.o.columns - opts.width) / 2)
  return opts
end

---@param buf integer
---@param layout? agents.Layout
---@return integer
function M.open(buf, layout)
  local config = require("agents.config").get()
  layout = layout or config.layout
  if layout == "float" then
    layout = config.float
  end

  ---@type integer
  local win
  if type(layout) == "table" then
    win = vim.api.nvim_open_win(buf, true, float_config(layout))
  elseif type(layout) == "function" then
    win = layout(buf)
  else
    if layout ~= "current" then
      vim.cmd(layout)
    end
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_buf(win, buf)
  return win
end

---@param session agents.Session
---@param layout? agents.Layout
---@return agents.Session
function M.show(session, layout)
  local wins = vim.fn.win_findbuf(session.buf)
  ---@type integer?
  local opened
  if #wins == 0 then
    opened = M.open(session.buf, layout)
  elseif vim.api.nvim_get_current_buf() ~= session.buf then
    vim.api.nvim_set_current_win(wins[1])
  end
  session.tab = vim.api.nvim_get_current_tabpage()
  if session.state ~= "exited" then
    vim.cmd.startinsert()
  end
  if opened then
    require("agents.events").emit("AgentsSessionShow", { id = session.id, win = opened })
  end
  return session
end

---@param session agents.Session
---@param tab? integer Restrict hiding to this tab; otherwise hide every view.
---@return agents.Session
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
      if alternate == session.buf or not vim.api.nvim_buf_is_valid(alternate) then
        alternate = vim.api.nvim_create_buf(true, false)
      end
      vim.api.nvim_win_set_buf(win, alternate)
    end
  end
  if #wins > 0 and session.job and session.job > 0 and not M.visible(session) then
    require("agents.events").emit("AgentsSessionHide", { id = session.id })
  end
  return session
end

return M
