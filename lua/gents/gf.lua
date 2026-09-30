local M = {}

---@class gents.gf.Map: vim.api.keyset.get_keymap
---@field buffer? integer

---@class gents.gf.Entry
---@field original? gents.gf.Map
---@field global? vim.api.keyset.get_keymap
---@field watch_global boolean
---@field callback fun(): string
---@field fallback string
---@field proxy gents.gf.Map

---@type table<integer, gents.gf.Entry>
local entries = {}
---@type table<integer, boolean>
local declined = {}
---@type table<integer, boolean>
local pending = {}
local enabled = false
local generation = 0
local depth = 0

---@param buf integer
---@param callback fun()
local function in_buffer(buf, callback)
  depth = depth + 1
  local ok, result = pcall(vim.api.nvim_buf_call, buf, callback)
  depth = depth - 1
  if not ok then
    error(result, 0)
  end
end

---@return vim.api.keyset.get_keymap?
local function global_map()
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
    if map.lhs == "gf" then
      return map
    end
  end
end

---@param lhs string
---@return gents.gf.Map?
local function mapping(lhs)
  ---@type gents.gf.Map
  local map = vim.fn.maparg(lhs, "n", false, true)
  return next(map) ~= nil and map or nil
end

---@param fallback string
---@param original? vim.api.keyset.get_keymap
local function proxy_map(fallback, original)
  if original then
    ---@type gents.gf.Map
    local proxy = vim.tbl_extend("force", original, {
      lhs = fallback,
      lhsraw = vim.api.nvim_replace_termcodes(fallback, true, true, true),
      buffer = 1,
    })
    proxy.lhsrawalt = nil
    -- mapset preserves expression/remapping flags and the defining script ID.
    vim.fn.mapset("n", false, proxy)
  else
    vim.keymap.set("n", fallback, "gf", { buffer = true })
  end
end

---@param buf integer
---@param entry gents.gf.Entry
---@return boolean owned
local function remove(buf, entry)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local owned = false
  in_buffer(buf, function()
    local current = mapping("gf")
    owned = current ~= nil and current.callback == entry.callback
    if owned then
      vim.keymap.del("n", "gf", { buffer = buf })
      if entry.original and entry.original.buffer == 1 then
        vim.fn.mapset("n", false, entry.original)
      end
    end
    if vim.deep_equal(mapping(entry.fallback), entry.proxy) then
      vim.keymap.del("n", entry.fallback, { buffer = buf })
    end
  end)
  return owned
end

---Called outside expression-map textlock, after a reference has been recognized.
function M.follow()
  local ok, result = pcall(require("gents").resume_at_cursor)
  if not ok then
    vim.notify(tostring(result), vim.log.levels.ERROR, { title = "gents.nvim" })
  end
end

---@param buf integer
function M.attach(buf)
  if not enabled or declined[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  in_buffer(buf, function()
    local existing = entries[buf]
    if existing then
      local current = mapping("gf")
      if
        current
        and current.callback == existing.callback
        and (not existing.watch_global or vim.deep_equal(global_map(), existing.global))
      then
        return
      end
      remove(buf, existing)
      entries[buf] = nil
      declined[buf] = true
      return
    end
    local original = mapping("gf")
    local fallback = "<Plug>(gents-gf-" .. buf .. ")"
    proxy_map(fallback, original)
    local global = global_map()
    local watch_global = not original or original.buffer ~= 1
    ---@return string
    local function run()
      if watch_global and not vim.deep_equal(global_map(), global) then
        -- A later global replacement must become effective even in this buffer.
        vim.keymap.del("n", "gf", { buffer = buf })
        proxy_map(fallback, global_map())
        local entry = entries[buf]
        if entry then
          entry.proxy = assert(mapping(fallback))
        end
        declined[buf] = true
        -- A RHS beginning with its own LHS is not remapped; use the private map
        -- for this last invocation, then let the global replacement take over.
        return fallback
      end
      local ok, reference = pcall(
        require("gents.references").parse,
        vim.api.nvim_get_current_line(),
        vim.api.nvim_win_get_cursor(0)[2],
        require("gents.config").get().tools
      )
      if not ok or reference then
        return "<Cmd>lua require('gents.gf').follow()<CR>"
      end
      return fallback
    end
    entries[buf] = {
      original = original,
      global = global,
      watch_global = watch_global,
      callback = run,
      fallback = fallback,
      proxy = assert(mapping(fallback)),
    }
    vim.keymap.set("n", "gf", run, {
      buffer = buf,
      expr = true,
      remap = true,
      nowait = original ~= nil and original.nowait == 1,
      silent = original ~= nil and original.silent == 1,
      desc = "Gents: follow conversation reference or original gf",
    })
  end)
end

---@param buf integer
local function queue(buf)
  -- Temporary nvim_buf_call switches can fire entry events on Neovim 0.12.
  if depth > 0 or pending[buf] then
    return
  end
  pending[buf] = true
  local scheduled = generation
  -- Let FileType/BufRead/terminal integrations finish installing their maps.
  vim.schedule(function()
    if scheduled ~= generation then
      return
    end
    pending[buf] = nil
    M.attach(buf)
  end)
end

---@param active boolean
function M.setup(active)
  generation = generation + 1
  pending = {}
  for buf, entry in pairs(entries) do
    if entry.watch_global and not vim.deep_equal(global_map(), entry.global) then
      declined[buf] = true
    end
    if not remove(buf, entry) then
      declined[buf] = true
    end
  end
  entries = {}
  enabled = active
  local group = vim.api.nvim_create_augroup("GentsGF", { clear = true })
  if not active then
    declined = {}
    return
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType", "TermOpen" }, {
    group = group,
    callback = function(ev)
      queue(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = group,
    callback = function(ev)
      local entry = entries[ev.buf]
      if entry then
        if not remove(ev.buf, entry) then
          declined[ev.buf] = true
        end
        entries[ev.buf] = nil
      end
      queue(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      entries[ev.buf], declined[ev.buf], pending[ev.buf] = nil, nil, nil
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      queue(buf)
    end
  end
end

return M
