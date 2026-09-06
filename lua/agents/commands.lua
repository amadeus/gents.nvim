local M = {}

---@type agents.CommandName[]
local subcommands = { "actions", "close", "focus", "hide", "new", "pick", "send", "toggle" }

---@return agents.CommandName[]
function M.names()
  return vim.list_slice(subcommands)
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

---@param opts { args: string, range?: integer, line1?: integer, line2?: integer }
---@return agents.Session?
function M.run(opts)
  local args = words(opts.args)
  local command = table.remove(args, 1) or "pick"
  local agents = require("agents")

  if opts.range and opts.range > 0 and command ~= "send" then
    error("agents: only send accepts a range", 0)
  end

  if command == "send" then
    ---@type agents.Item[]?
    local items
    if #args > 0 then
      items = {}
      local prompts = require("agents.config").get().prompts
      for _, name in ipairs(args) do
        vim.list_extend(items, prompts[name] or { name })
      end
    end
    if opts.range and opts.range > 0 then
      return require("agents.send").run(items or { "selection" }, nil, {
        line1 = assert(opts.line1),
        line2 = assert(opts.line2),
      })
    end
    return agents.send(items)
  end

  if command == "new" then
    local name = table.remove(args, 1)
    return agents.new(name, #args > 0 and { args = args } or nil)
  end

  if command == "hide" or command == "close" then
    local target = #args > 0 and table.concat(args, " ") or nil
    return agents[command](tonumber(target) or target)
  end

  if command == "actions" or command == "focus" or command == "toggle" or command == "pick" then
    if #args > 0 then
      error("agents: " .. command .. " does not accept arguments", 0)
    end
    return agents[command]()
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

  if command == "new" then
    if remainder:find("%s") then
      return {}
    end
    local tools = require("agents.tools")
    return matching(tools.names(require("agents.config").get().tools), arglead)
  end

  if command == "send" then
    local names = require("agents.providers").names()
    for name in pairs(require("agents.config").get().prompts) do
      if not vim.list_contains(names, name) then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    return matching(names, arglead)
  end

  if command == "hide" or command == "close" then
    ---@type string[]
    local labels = {}
    for _, session in ipairs(require("agents").sessions()) do
      labels[#labels + 1] = session.label
    end

    -- Neovim replaces only ArgLead, even when the completed label contains spaces.
    local preceding = table.concat(words(remainder:sub(1, #remainder - #arglead)), " ")
    if preceding ~= "" then
      preceding = preceding .. " "
    end
    return matching(labels, preceding .. arglead, #preceding)
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
