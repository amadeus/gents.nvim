local M = {}

---@class agents.keys.Mapping
---@field mode agents.KeyMode
---@field callback fun()

---@type agents.Keymap[]
local keys = {}
---@type agents.keys.Mapping[]
local global_maps = {}
---@type table<integer, agents.keys.Mapping[]>
local buffer_maps = {}
---@type table<agents.KeyAction, boolean>
local actions = {
  actions = true,
  new = true,
  toggle = true,
  pick = true,
  hide = true,
  close = true,
  send = true,
}
---@type table<agents.KeyMode, boolean>
local allowed_modes = { n = true, x = true, t = true }

---@param key agents.Keymap
---@return agents.KeyMode[]
local function modes(key)
  local mode = key.mode
  if type(mode) == "string" then
    return { mode }
  end
  return mode or { "n", "x", "t" }
end

---@param entries agents.Keymap[]
function M.validate(entries)
  assert(type(entries) == "table" and vim.islist(entries), "agents: keys must be a list")
  for index, key in ipairs(entries) do
    local prefix = "agents: keys[" .. index .. "]"
    assert(type(key) == "table", prefix .. " must be a keymap table")
    assert(type(key[1]) == "string" and key[1] ~= "", prefix .. " requires a non-empty key")
    assert(
      type(key[2]) == "function" or (type(key[2]) == "string" and actions[key[2]]),
      prefix .. " action must be actions, new, toggle, pick, hide, close, send, or a function"
    )
    assert(
      key.mode == nil
        or type(key.mode) == "string"
        or (type(key.mode) == "table" and vim.islist(key.mode)),
      prefix .. " mode must be n, x, t, or a list of those modes"
    )
    for _, mode in ipairs(modes(key)) do
      assert(allowed_modes[mode], prefix .. " mode must be n, x, or t")
    end
  end
end

---@param mappings agents.keys.Mapping[]
---@param buf? integer
local function remove(mappings, buf)
  if buf and not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, mapping in ipairs(mappings) do
    local existing = buf and vim.api.nvim_buf_get_keymap(buf, mapping.mode)
      or vim.api.nvim_get_keymap(mapping.mode)
    for _, map in ipairs(existing) do
      -- A user may have replaced this mapping since the last setup call.
      if map.callback == mapping.callback then
        vim.keymap.del(mapping.mode, map.lhs, { buffer = buf })
      end
    end
  end
end

---@param action agents.KeyAction|fun()
---@return fun()
local function callback(action)
  return function()
    if type(action) == "function" then
      action()
    else
      require("agents")[action]()
    end
  end
end

---@param key agents.Keymap
---@param mode agents.KeyMode
---@param buf? integer
---@return agents.keys.Mapping
local function install(key, mode, buf)
  local run = callback(key[2])
  vim.keymap.set(mode, key[1], run, {
    buffer = buf,
    silent = true,
    desc = type(key[2]) == "string" and "Agents " .. key[2] or "Agents callback",
  })
  return { mode = mode, callback = run }
end

---@param buf integer
function M.attach(buf)
  local previous = buffer_maps[buf]
  if previous then
    remove(previous, buf)
  else
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        buffer_maps[buf] = nil
      end,
    })
  end
  ---@type agents.keys.Mapping[]
  local mappings = {}
  for _, key in ipairs(keys) do
    for _, mode in ipairs(modes(key)) do
      if mode == "t" then
        mappings[#mappings + 1] = install(key, mode, buf)
      end
    end
  end
  buffer_maps[buf] = mappings
end

---@param entries agents.Keymap[]
function M.setup(entries)
  remove(global_maps)
  keys = vim.deepcopy(entries)
  global_maps = {}
  for _, key in ipairs(keys) do
    for _, mode in ipairs(modes(key)) do
      if mode ~= "t" then
        global_maps[#global_maps + 1] = install(key, mode)
      end
    end
  end
  for _, session in ipairs(require("agents.session").list()) do
    M.attach(session.buf)
  end
end

return M
