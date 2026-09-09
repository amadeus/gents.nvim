local M = {}

---@param opts? gents.SetupOptions
function M.setup(opts)
  local config = require("gents.config").setup(opts)
  require("gents.keys").setup(config.keys)
end

---@param tool? string
---@param opts? gents.NewOptions
---@return gents.Session?
function M.new(tool, opts)
  if tool == nil then
    return require("gents.picker").tools(function(selected, launch_opts)
      return M.new(selected.name, launch_opts)
    end, opts)
  end
  local definition = require("gents.config").get().tools[tool]
  assert(definition, "gents: unknown tool: " .. tostring(tool))
  return require("gents.session").new(definition, opts)
end

---@return gents.Session[]
function M.sessions()
  return require("gents.session").list()
end

---@return gents.Session?
function M.current()
  return require("gents.session").current()
end

---@return gents.Status[]
function M.status()
  ---@type gents.Status[]
  local result = {}
  for _, session in ipairs(M.sessions()) do
    result[#result + 1] = {
      id = session.id,
      tool = session.tool.name,
      label = session.label,
      title = session.title,
      visible = require("gents.window").visible(session),
      state = session.state,
      cwd = session.cwd,
    }
  end
  return result
end

---@param id integer
---@return gents.ReadyEvent
function M.ready(id)
  local session = require("gents.session").get(id)
  assert(session, "gents: no session with id " .. tostring(id))
  return require("gents.events").ready(session, "hook")
end

---Omitting items opens the context picker.
---@param items? gents.Item[]
---@param opts? gents.SendOptions
---@return gents.Session?
function M.send(items, opts)
  return require("gents.send").run(items, opts)
end

---@param name string
---@param spec gents.Provider
function M.provider(name, spec)
  require("gents.providers").register(name, spec)
end

---@param target? gents.Target
---@param opts? gents.ShowOptions
---@return gents.Session?
function M.show(target, opts)
  return require("gents.target").with(target, function(session)
    return require("gents.window").show(session, opts and opts.layout)
  end)
end

---@param target? gents.Target
---@return gents.Session?
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

---@param target? gents.Target
---@return gents.Session?
function M.hide(target)
  return require("gents.target").with(target, require("gents.window").hide)
end

---@param target? gents.Target
---@return gents.Session?
function M.close(target)
  return require("gents.target").with(target, require("gents.session").close)
end

---@param target? gents.Target
---@return gents.Session?
function M.pick(target)
  if target ~= nil then
    return M.show(target)
  end
  local sessions = M.sessions()
  if #sessions == 0 then
    return M.new()
  end
  return require("gents.picker").sessions(sessions, function(session)
    return M.show(session.id)
  end)
end

---Open a picker for the top-level commands.
---@param range? { line1: integer, line2: integer } Explicit Ex range for send.
---@return nil
function M.actions(range)
  local ctx = range and require("gents.context").capture(range) or nil
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" or mode == "s" or mode == "S" or mode == "\19" then
    if not ctx and not M.current() then
      ctx = require("gents.context").capture()
    end
    vim.cmd.normal({ args = { "\27" }, bang = true })
  end
  require("gents.picker").commands(function(command)
    require("gents.commands").run({
      args = command,
      context = ctx,
      range = range and 1 or nil,
      line1 = range and range.line1,
      line2 = range and range.line2,
    })
  end)
end

---@param target? gents.Target
---@return gents.Session?
function M.toggle(target)
  local window = require("gents.window")
  local tab = vim.api.nvim_get_current_tabpage()
  if target == nil and #M.sessions() == 0 then
    return M.new()
  end
  return require("gents.target").with(target, function(session)
    if window.visible(session, tab) then
      return window.hide(session, tab)
    end
    return window.show(session)
  end)
end

return M
