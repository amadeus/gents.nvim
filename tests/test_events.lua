local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality

---@class gents.test.EventObservation
---@field name string
---@field data gents.SessionEvent

---@type gents.test.EventObservation[]
local observed = {}
---@type integer
local group

local function reset()
  ---@type integer[]
  local jobs = {}
  for _, session in ipairs(gents.sessions()) do
    if session.job and session.job > 0 then
      jobs[#jobs + 1] = session.job
    end
  end
  H.reset()
  if #jobs > 0 then
    vim.fn.jobwait(jobs, 2000)
  end
end

---@param name gents.EventName
---@return gents.test.EventObservation[]
local function events(name)
  return vim.tbl_filter(
    ---@param event gents.test.EventObservation
    ---@return boolean
    function(event)
      return event.name == name
    end,
    observed
  )
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      reset()
      observed = {}
      group = vim.api.nvim_create_augroup("GentsEventsTest", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "Gents*",
        callback = function(ev)
          observed[#observed + 1] = { name = ev.match, data = vim.deepcopy(ev.data) }
        end,
      })
    end,
    post_case = function()
      vim.api.nvim_del_augroup_by_id(group)
      reset()
    end,
  },
})

T["lifecycle events occur once per plugin transition"] = function()
  local session = H.new()
  local first_win = vim.api.nvim_get_current_win()
  eq(observed, {
    { name = "GentsSessionStart", data = { id = session.id } },
    { name = "GentsSessionShow", data = { id = session.id, win = first_win } },
  })
  gents.show(session.id)
  eq(#observed, 2)
  vim.cmd.split()
  gents.hide(session.id)
  gents.hide(session.id)
  eq(#events("GentsSessionHide"), 1)
  gents.show(session.id)
  local shown = events("GentsSessionShow")
  eq(#shown, 2)
  eq(shown[2].data, { id = session.id, win = vim.api.nvim_get_current_win() })
  gents.close(session.id)
  H.wait(function()
    return #events("GentsSessionExit") == 1
  end)
  eq(#events("GentsSessionStart"), 1)
  eq(#events("GentsSessionShow"), 2)
  eq(#events("GentsSessionHide"), 2)
  eq(events("GentsSessionExit")[1].data.id, session.id)
  eq(type(events("GentsSessionExit")[1].data.exit_code), "number")
end

T["hide emits only when the last view across tabs is removed"] = function()
  local session = H.new()
  vim.cmd.tabnew()
  vim.cmd.vsplit()
  vim.api.nvim_win_set_buf(0, session.buf)
  gents.hide(session.id)
  eq(#events("GentsSessionHide"), 0)
  vim.cmd.tabprevious()
  eq(#events("GentsSessionShow"), 1)
  gents.hide(session.id)
  eq(#events("GentsSessionHide"), 1)
end

T["show in the current window emits only when it adds a session view"] = function()
  local session = H.new()
  vim.cmd.tabnew()
  local origin = vim.api.nvim_get_current_win()
  gents.show(session.id, { layout = "current" })
  local shown = events("GentsSessionShow")
  eq(#shown, 2)
  eq(shown[2].data, { id = session.id, win = origin })
  gents.show(session.id, { layout = "current" })
  eq(#events("GentsSessionShow"), 2)
  eq(vim.api.nvim_get_current_win(), origin)
  eq(#vim.fn.win_findbuf(session.buf), 2)
end

T["process exit emits its actual exit code and keeps the buffer"] = function()
  local session = H.new({ cmd = { "sh", "-c", "exit 7" } })
  H.wait(function()
    return #events("GentsSessionExit") == 1
  end)
  eq(events("GentsSessionExit")[1].data, { id = session.id, exit_code = 7 })
  eq(session.state, "exited")
  eq(gents.sessions(), { session })
  eq(vim.api.nvim_buf_is_valid(session.buf), true)
end

T["a start listener may replace the initial window without a stale show event"] = function()
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GentsSessionStart",
    callback = function(ev)
      gents.hide(ev.data.id)
      gents.show(ev.data.id, { layout = "tabnew" })
    end,
  })
  local session = H.new()
  eq(events("GentsSessionShow"), {
    {
      name = "GentsSessionShow",
      data = { id = session.id, win = vim.api.nvim_get_current_win() },
    },
  })
end

T["successful auto-close emits exit and hides once"] = function()
  gents.setup({ on_exit = "close", tools = { cat = { cmd = { "cat" } } } })
  local session = H.new({ cmd = { "sh", "-c", "exit 0" } })
  H.wait(function()
    return #gents.sessions() == 0
  end)
  eq(events("GentsSessionExit"), {
    { name = "GentsSessionExit", data = { id = session.id, exit_code = 0 } },
  })
  eq(#events("GentsSessionHide"), 1)
  eq(vim.api.nvim_buf_is_valid(session.buf), false)
end

T["failed launches do not emit lifecycle events"] = function()
  test.expect.error(function()
    H.new({ cmd = { "/gents-test-missing-executable" } })
  end)
  eq(observed, {})
  eq(gents.sessions(), {})
end

return T
