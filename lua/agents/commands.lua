local M = {}

---@type agents.CommandName[]
local subcommands = { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" }

---@param actions_only? boolean Exclude the actions menu from its own choices.
---@return agents.CommandName[]
function M.names(actions_only)
  return vim.list_slice(subcommands, actions_only and 2 or 1)
end

---@param value string
---@return string[]
local function words(value)
  ---@type string[]
  local result = {}
  for word in value:gmatch("%S+") do
    result[#result + 1] = word
  end
  return result
end

---@param candidates string[]
---@param prefix string
---@param offset? integer
---@return string[]
local function matching(candidates, prefix, offset)
  ---@type string[]
  local result = {}
  for _, candidate in ipairs(candidates) do
    if vim.startswith(candidate, prefix) then
      result[#result + 1] = candidate:sub((offset or 0) + 1)
    end
  end
  return result
end

---@param args string[]
---@return integer|string?
local function target_from(args)
  local target = #args > 0 and table.concat(args, " ") or nil
  local id = tonumber(target)
  if id and id == math.floor(id) then
    return math.floor(id)
  end
  return target
end

---@class agents.commands.Options
---@field args string
---@field range? integer
---@field line1? integer
---@field line2? integer
---@field context? agents.Context Source captured before an actions picker opened.

---@param opts agents.commands.Options
---@return agents.Session?
function M.run(opts)
  local args = words(opts.args)
  local command = table.remove(args, 1) or "pick"
  local agents = require("agents")

  if command == "actions" and #args > 0 then
    command = table.remove(args, 1)
    assert(command ~= "actions", "agents: actions cannot select itself")
  end

  ---@type { line1: integer, line2: integer }?
  local range
  if opts.range and opts.range > 0 then
    range = { line1 = assert(opts.line1), line2 = assert(opts.line2) }
  end
  if range and command ~= "send" and command ~= "actions" then
    error("agents: only send accepts a range", 0)
  end

  if command == "send" then
    ---@type agents.SendOptions?
    local send_opts
    for i, arg in ipairs(args) do
      if arg == "--target" then
        local target = target_from(vim.list_slice(args, i + 1))
        assert(target ~= nil, "agents: --target requires a session id or label")
        send_opts = { target = target }
        args = vim.list_slice(args, 1, i - 1)
        break
      end
    end
    ---@type agents.Item[]?
    local items
    if #args > 0 then
      items = {}
      local prompts = require("agents.config").get().prompts
      for _, name in ipairs(args) do
        vim.list_extend(items, prompts[name] or { name })
      end
    end
    if range and not items then
      items = { "selection" }
    end
    if opts.context then
      return require("agents.send").from_context(opts.context, items, send_opts)
    elseif range then
      return require("agents.send").run(items, send_opts, range)
    end
    return agents.send(items, send_opts)
  end

  if command == "new" then
    local name = table.remove(args, 1)
    return agents.new(name, #args > 0 and { args = args } or nil)
  end

  if
    command == "hide"
    or command == "close"
    or command == "pick"
    or command == "focus"
    or command == "toggle"
  then
    return agents[command](target_from(args))
  end

  if command == "actions" then
    if range then
      return agents.actions(range)
    end
    return agents.actions()
  end

  error(
    "agents: unknown command '"
      .. command
      .. "' (expected: "
      .. table.concat(subcommands, ", ")
      .. ")",
    0
  )
end

---@param arglead string
---@param remainder string
---@return string[]
local function complete_target(arglead, remainder)
  ---@type string[]
  local candidates = {}
  for _, session in ipairs(require("agents").sessions()) do
    candidates[#candidates + 1] = session.label
  end

  -- Neovim replaces only ArgLead, even when the completed label contains spaces.
  local preceding = table.concat(words(remainder:sub(1, #remainder - #arglead)), " ")
  if preceding ~= "" then
    preceding = preceding .. " "
  else
    for _, session in ipairs(require("agents").sessions()) do
      candidates[#candidates + 1] = tostring(session.id)
    end
  end
  return matching(candidates, preceding .. arglead, #preceding)
end

---@param arglead string
---@param cmdline string
---@param cursorpos integer
---@return string[]
function M.complete(arglead, cmdline, cursorpos)
  local line = cmdline:sub(1, cursorpos)
  local args = line:match("^%s*:?%S+%s+(.*)$") or ""
  ---@type string?, string?
  local command, remainder = args:match("^(%S+)%s+(.*)$")
  if not command or not remainder then
    return matching(subcommands, arglead)
  end

  if command == "actions" then
    ---@type string?, string?
    local action, action_args = remainder:match("^(%S+)%s+(.*)$")
    if not action or not action_args then
      return matching(M.names(true), arglead)
    end
    command, remainder = action, action_args
  end

  if command == "new" then
    if remainder:find("%s") then
      return {}
    end
    local tools = require("agents.tools")
    return matching(tools.names(require("agents.config").get().tools), arglead)
  end

  if command == "send" then
    -- Only the first --target separates providers from the full session label.
    local target = (" " .. remainder):match("%s%-%-target%s+(.*)$")
    if target then
      return complete_target(arglead, target)
    end
    local names = require("agents.providers").names()
    for name in pairs(require("agents.config").get().prompts) do
      if not vim.list_contains(names, name) then
        names[#names + 1] = name
      end
    end
    if not vim.list_contains(names, "--target") then
      names[#names + 1] = "--target"
    end
    table.sort(names)
    return matching(names, arglead)
  end

  if
    command == "hide"
    or command == "close"
    or command == "pick"
    or command == "focus"
    or command == "toggle"
  then
    return complete_target(arglead, remainder)
  end

  return {}
end

function M.setup()
  vim.api.nvim_create_user_command("Agents", M.run, {
    nargs = "*",
    range = true,
    complete = M.complete,
    desc = "Manage agent CLI sessions",
    force = true,
  })
end

return M
