local M = {}

---@alias gents.context.Position [integer, integer, integer, integer]
---@alias gents.context.Segment [gents.context.Position, gents.context.Position]
---@class gents.context.Selection
---@field lines string[]
---@field segments gents.context.Segment[]

-- Public ranges use byte columns. Keep the actual selection separately because
-- partial tabs and virtual block columns cannot fit in those two endpoints.
---@type table<gents.Context, gents.context.Selection>
local selections = setmetatable({}, { __mode = "k" })

---@param ctx gents.Context
---@param first gents.context.Position
---@param last gents.context.Position
---@param mode string
---@param exclusive boolean
---@return gents.context.Selection
local function read_selection(ctx, first, last, mode, exclusive)
  return vim.api.nvim_win_call(ctx.win, function()
    return {
      lines = vim.fn.getregion(first, last, { type = mode, exclusive = exclusive }),
      segments = vim.fn.getregionpos(
        first,
        last,
        { type = mode, exclusive = exclusive, eol = true }
      ),
    }
  end)
end

---@param range? { line1: integer, line2: integer } An explicit Ex range is linewise.
---@return gents.Context
function M.capture(range)
  local win = vim.api.nvim_get_current_win()
  ---@type gents.Context
  local ctx = {
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    cwd = vim.api.nvim_win_call(win, function()
      return vim.fn.getcwd(0)
    end),
    cursor = vim.api.nvim_win_get_cursor(win),
  }
  local mode = vim.fn.mode()
  mode = mode == "s" and "v" or mode == "S" and "V" or mode == "\19" and "\22" or mode
  ---@type gents.context.Position?, gents.context.Position?
  local first, last
  local exclusive = false
  if range then
    assert(
      range.line1 >= 1
        and range.line1 <= range.line2
        and range.line2 <= vim.api.nvim_buf_line_count(ctx.buf),
      "gents: invalid source line range"
    )
    first, last = { ctx.buf, range.line1, 1, 0 }, { ctx.buf, range.line2, 1, 0 }
    mode = "V"
  elseif
    win == vim.api.nvim_get_current_win() and (mode == "v" or mode == "V" or mode == "\22")
  then
    local anchor, cursor = vim.fn.getpos("v"), vim.fn.getpos(".")
    first, last =
      { ctx.buf, anchor[2], anchor[3], anchor[4] }, { ctx.buf, cursor[2], cursor[3], cursor[4] }
    if mode == "\22" and vim.fn.getcurpos()[5] == vim.v.maxcol then
      last[3] = vim.v.maxcol
    end
    exclusive = vim.o.selection == "exclusive"
  end
  if first and last then
    local selection = read_selection(ctx, first, last, mode, exclusive)
    local start = selection.segments[1]
    local finish = selection.segments[#selection.segments]
    if start and finish then
      ctx.range = {
        kind = mode == "V" and "line" or mode == "\22" and "block" or "char",
        start = { start[1][2], mode == "V" and 0 or math.max(0, start[1][3] - 1) },
        finish = { finish[2][2], mode == "V" and 0 or math.max(0, finish[2][3] - 1) },
      }
      selections[ctx] = selection
    end
  end
  return ctx
end

---@param ctx gents.Context
---@return gents.context.Selection?
local function selection_for(ctx)
  local range = ctx.range
  if not range then
    return nil
  end
  if selections[ctx] then
    return selections[ctx]
  end
  return read_selection(
    ctx,
    { ctx.buf, range.start[1], range.start[2] + 1, 0 },
    { ctx.buf, range.finish[1], range.finish[2] + 1, 0 },
    range.kind == "line" and "V" or range.kind == "block" and "\22" or "v",
    false
  )
end

---@param ctx gents.Context
---@return string[]?
function M.selection(ctx)
  local selection = selection_for(ctx)
  return selection and vim.deepcopy(selection.lines) or nil
end

---Per-line byte spans also preserve block selections for diagnostic filtering.
---@param ctx gents.Context
---@return gents.context.Segment[]?
function M.segments(ctx)
  local selection = selection_for(ctx)
  return selection and vim.deepcopy(selection.segments) or nil
end

return M
