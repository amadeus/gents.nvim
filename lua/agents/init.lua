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
  local window = require("agents.window")
  local tab = vim.api.nvim_get_current_tabpage()
  local current = M.current()
  if current then
    return window.hide(current, tab)
  end
  local sessions = M.sessions()
  local hidden = false
  for _, session in ipairs(sessions) do
    if window.visible(session, tab) then
      window.hide(session, tab)
      hidden = true
    end
  end
  if hidden then
    return
  end
  if #sessions == 0 then
    return M.new()
  elseif #sessions == 1 then
    return M.show(sessions[1].id)
  end
  return M.pick()
end

return M
