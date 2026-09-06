local M = {}
local context = require("agents.context")
local builtin_order = {
  "line",
  "selection",
  "file",
  "buffer",
  "messages",
  "diagnostics",
  "quickfix",
  "terminal",
}
---@type table<string, agents.Provider>
local registry = {}

---@param ctx agents.Context
---@return string?
local function filename(ctx)
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  local buftype = vim.bo[ctx.buf].buftype
  if name ~= "" and (buftype == "" or buftype == "help") then
    return name
  end
end

---@param ctx agents.Context
---@param path string
---@return string
local function display_path(ctx, path)
  return path == "" and "[No Name]" or require("agents.render").path(path, ctx.cwd)
end

---@param lines string[]
---@param tabstop integer
---@return string
local function dedent(lines, tabstop)
  ---@type integer?
  local minimum
  for _, line in ipairs(lines) do
    if line:find("%S") then
      local width = 0
      ---@type string
      local indent = line:match("^[ \t]*") or ""
      for column = 1, #indent do
        local char = indent:sub(column, column)
        width = width + (char == "\t" and tabstop - width % tabstop or 1)
      end
      minimum = math.min(minimum or width, width)
    end
  end
  for i, line in ipairs(lines) do
    local width, column = 0, 1
    while width < (minimum or 0) and column <= #line do
      local char = line:sub(column, column)
      if char ~= " " and char ~= "\t" then
        break
      end
      width = width + (char == "\t" and tabstop - width % tabstop or 1)
      column = column + 1
    end
    lines[i] = string.rep(" ", math.max(0, width - (minimum or 0))) .. line:sub(column)
  end
  return table.concat(lines, "\n")
end

registry.file = {
  desc = "Reference the current file",
  render = function(ctx)
    local path = filename(ctx)
    return path and { { path = path } } or nil
  end,
}

registry.line = {
  desc = "Reference current or selected lines",
  render = function(ctx)
    local path = filename(ctx)
    if not path then
      return nil
    end
    return {
      {
        path = path,
        range = {
          kind = "line",
          start = { ctx.range and ctx.range.start[1] or ctx.cursor[1], 0 },
          finish = { ctx.range and ctx.range.finish[1] or ctx.cursor[1], 0 },
        },
      },
    }
  end,
}

registry.selection = {
  desc = "Copy selected text",
  render = function(ctx)
    local lines = context.selection(ctx)
    if not lines then
      return nil
    end
    return { { code = dedent(lines, vim.bo[ctx.buf].tabstop), ft = vim.bo[ctx.buf].filetype } }
  end,
}

registry.buffer = {
  desc = "Copy entire buffer text",
  render = function(ctx)
    return {
      {
        code = table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n"),
        ft = vim.bo[ctx.buf].filetype,
      },
    }
  end,
}

---@param diagnostic vim.Diagnostic
---@param segments agents.context.Segment[]
---@param linewise boolean
---@return boolean
local function intersects(diagnostic, segments, linewise)
  for _, segment in ipairs(segments) do
    local row = segment[1][2] - 1
    local first = linewise and 0 or math.max(0, segment[1][3] - 1)
    local last = linewise and math.huge or math.max(0, segment[2][3] - 1)
    local starts_before = diagnostic.lnum < row
      or (diagnostic.lnum == row and diagnostic.col <= last)
    local ends_after = diagnostic.end_lnum > row
      or (diagnostic.end_lnum == row and diagnostic.end_col > first)
    local is_point = diagnostic.lnum == diagnostic.end_lnum and diagnostic.col == diagnostic.end_col
    if
      starts_before
      and (ends_after or (is_point and diagnostic.lnum == row and diagnostic.col >= first))
    then
      return true
    end
  end
  return false
end

registry.diagnostics = {
  desc = "Buffer diagnostics",
  render = function(ctx)
    local diagnostics = vim.diagnostic.get(ctx.buf)
    table.sort(diagnostics, function(a, b)
      if a.lnum ~= b.lnum then
        return a.lnum < b.lnum
      elseif a.col ~= b.col then
        return a.col < b.col
      elseif a.severity ~= b.severity then
        return a.severity < b.severity
      end
      return a.message < b.message
    end)
    local segments = context.segments(ctx)
    local path = display_path(ctx, vim.api.nvim_buf_get_name(ctx.buf))
    ---@type string[]
    local lines = {}
    for _, diagnostic in ipairs(diagnostics) do
      if
        not segments
        or intersects(diagnostic, segments, ctx.range and ctx.range.kind == "line" or false)
      then
        lines[#lines + 1] = string.format(
          "%s:%d:%d: %s: %s",
          path,
          diagnostic.lnum + 1,
          diagnostic.col + 1,
          vim.diagnostic.severity[diagnostic.severity],
          diagnostic.message
        )
      end
    end
    return #lines > 0 and { { text = table.concat(lines, "\n") } } or nil
  end,
}

registry.quickfix = {
  desc = "Quickfix entries",
  render = function(ctx)
    ---@type vim.quickfix.entry[]
    local entries = vim.fn.getqflist()
    ---@type string[]
    local lines = {}
    for _, entry in ipairs(entries) do
      local path = entry.bufnr and entry.bufnr > 0 and vim.api.nvim_buf_get_name(entry.bufnr)
        or entry.filename
        or ""
      ---@type string
      local location = path ~= "" and display_path(ctx, path) or ""
      if entry.lnum and entry.lnum > 0 then
        location = location .. ":" .. entry.lnum
        if entry.col and entry.col > 0 then
          location = string.format("%s:%d", location, entry.col)
        end
      end
      lines[#lines + 1] = (location ~= "" and location .. ": " or "") .. (entry.text or "")
    end
    return #lines > 0 and { { text = table.concat(lines, "\n") } } or nil
  end,
}

---Read terminal context directly, or use an inline item to choose a per-send limit.
---@param ctx agents.Context
---@param limit? integer Maximum lines after trimming trailing blanks; defaults to 1000.
---@return agents.Part[]?
function M.terminal(ctx, limit)
  limit = limit or 1000
  assert(
    type(limit) == "number" and limit > 0 and limit % 1 == 0,
    "agents: terminal line limit must be a positive integer"
  )
  if vim.bo[ctx.buf].buftype ~= "terminal" then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)
  while #lines > 0 and not lines[#lines]:find("%S") do
    table.remove(lines)
  end
  if #lines == 0 then
    return nil
  end
  return { { code = table.concat(lines, "\n", math.max(1, #lines - limit + 1)), ft = "text" } }
end

registry.terminal = { desc = "Copt terminal scrollback", render = M.terminal }

registry.messages = {
  desc = "Copy :messages history",
  render = function()
    local output = vim.api.nvim_exec2("messages", { output = true }).output
    return output:find("%S") and { { text = output } } or nil
  end,
}

---@param name string
---@param spec agents.Provider
---@return nil
function M.register(name, spec)
  assert(
    type(name) == "string" and name:match("^%S+$"),
    "agents: provider name must be nonempty and contain no whitespace"
  )
  assert(
    type(spec) == "table" and type(spec.desc) == "string",
    "agents: provider requires a description"
  )
  assert(type(spec.render) == "function", "agents: provider requires a render function")
  registry[name] = spec
end

---@param name string
---@return agents.Provider?
function M.get(name)
  return registry[name]
end

---@return string[]
function M.names()
  local names = vim.deepcopy(builtin_order)
  ---@type string[]
  local custom = {}
  for name in pairs(registry) do
    if not vim.list_contains(builtin_order, name) then
      custom[#custom + 1] = name
    end
  end
  table.sort(custom)
  vim.list_extend(names, custom)
  return names
end

return M
