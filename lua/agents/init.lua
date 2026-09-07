local M = {}

---@param opts? agents.SetupOptions
function M.setup(opts)
  local config = require("agents.config").setup(opts)
  require("agents.keys").setup(config.keys)
end

---@param tool? string
---@param opts? agents.NewOptions
---@return agents.Session?
function M.new(tool, opts)
  if tool == nil then
    return require("agents.picker").tools(function(selected, launch_opts)
      return M.new(selected.name, launch_opts)
    end, opts)
  end
  local definition = require("agents.config").get().tools[tool]
  assert(definition, "agents: unknown tool: " .. tostring(tool))
  return require("agents.session").new(definition, opts)
end

---@return agents.Session[]
function M.sessions()
  return require("agents.session").list()
end

---@return agents.Session?
function M.current()
  return require("agents.session").current()
end

---@return agents.Status[]
function M.status()
  ---@type agents.Status[]
  local result = {}
  for _, session in ipairs(M.sessions()) do
    result[#result + 1] = {
      id = session.id,
      tool = session.tool.name,
      label = session.label,
      title = session.title,
      visible = require("agents.window").visible(session),
      state = session.state,
      cwd = session.cwd,
    }
  end
  return result
end

---@param id integer
---@return agents.ReadyEvent
function M.ready(id)
  local session = require("agents.session").get(id)
  assert(session, "agents: no session with id " .. tostring(id))
  return require("agents.events").ready(session, "hook")
end

---Omitting items opens the context picker.
---@param items? agents.Item[]
---@param opts? agents.SendOptions
---@return agents.Session?
function M.send(items, opts)
  return require("agents.send").run(items, opts)
end

---@param name string
---@param spec agents.Provider
function M.provider(name, spec)
  require("agents.providers").register(name, spec)
end

---@param target? agents.Target
---@param opts? agents.ShowOptions
---@return agents.Session?
function M.show(target, opts)
  return require("agents.target").with(target, function(session)
    return require("agents.window").show(session, opts and opts.layout)
  end)
end

---@param target? agents.Target
---@return agents.Session?
function M.focus(target)
  if target ~= nil then
    return M.show(target)
  end
  if M.current() then
    vim.cmd.wincmd("p")
    vim.cmd.stopinsert()
    return
  end
  if #M.sessions() == 0 then
    return M.new()
  end
  return M.show()
end

---@param target? agents.Target
---@return agents.Session?
function M.hide(target)
  return require("agents.target").with(target, require("agents.window").hide)
end

---@param target? agents.Target
---@return agents.Session?
function M.close(target)
  return require("agents.target").with(target, require("agents.session").close)
end

---@param target? agents.Target
---@return agents.Session?
function M.pick(target)
  if target ~= nil then
    return M.show(target)
  end
  local sessions = M.sessions()
  if #sessions == 0 then
    return M.new()
  end
  return require("agents.picker").sessions(sessions, function(session)
    return M.show(session.id)
  end)
end

---Open a picker for the top-level commands.
---@param range? { line1: integer, line2: integer } Explicit Ex range for send.
---@return nil
function M.actions(range)
  local ctx = range and require("agents.context").capture(range) or nil
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" or mode == "s" or mode == "S" or mode == "\19" then
    if not ctx and not M.current() then
      ctx = require("agents.context").capture()
    end
    vim.cmd.normal({ args = { "\27" }, bang = true })
  end
  require("agents.picker").commands(function(command)
    require("agents.commands").run({
      args = command,
      context = ctx,
      range = range and 1 or nil,
      line1 = range and range.line1,
      line2 = range and range.line2,
    })
  end)
end

---@param target? agents.Target
---@return agents.Session?
function M.toggle(target)
  local window = require("agents.window")
  local tab = vim.api.nvim_get_current_tabpage()
  if target == nil and #M.sessions() == 0 then
    return M.new()
  end
  return require("agents.target").with(target, function(session)
    if window.visible(session, tab) then
      return window.hide(session, tab)
    end
    return window.show(session)
  end)
end

return M
