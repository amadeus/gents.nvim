local M = {}

---@param opts? agents.SetupOptions
function M.setup(opts)
  require("agents.config").setup(opts)
end

---@param tool? string
---@param opts? agents.NewOptions
---@return agents.Session?
function M.new(tool, opts)
  if tool == nil then
    return require("agents.picker").tools(function(selected)
      return M.new(selected.name, opts)
    end)
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
function M.hide(target)
  return require("agents.target").with(target, require("agents.window").hide)
end

---@param target? agents.Target
---@return agents.Session?
function M.close(target)
  return require("agents.target").with(target, require("agents.session").close)
end

---@return nil
function M.pick()
  local sessions = M.sessions()
  if #sessions == 0 then
    return M.new()
  end
  return require("agents.picker").sessions(sessions, function(session)
    return M.show(session.id)
  end)
end

---@return agents.Session?
function M.toggle()
  local current = M.current()
  if current then
    return M.hide(current.id)
  end
  local sessions = M.sessions()
  if #sessions == 0 then
    return M.new()
  end
  return M.show()
end

return M
