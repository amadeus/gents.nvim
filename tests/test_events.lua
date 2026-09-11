local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality

---@class gents.test.EventObservation
---@field name string
---@field data gents.SessionEvent|gents.ReadyEvent

---@class gents.test.ReadyObservation: gents.test.EventObservation
---@field data gents.ReadyEvent

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

---@overload fun(name: "GentsReady"): gents.test.ReadyObservation[]
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

T["ready signals do not change the send-readiness state"] = function()
  local session = H.new()
  local data = gents.ready(session.id)
  eq(data, {
    id = session.id,
    label = session.label,
    tool = "cat",
    buf = session.buf,
    win = vim.api.nvim_get_current_win(),
    visible = true,
    focused = true,
    source = "hook",
  })
  eq(events("GentsReady")[1].data, data)
  eq(session.state, "starting")
end

T["hook ready distinguishes visible and hidden sessions"] = function()
  local source = vim.api.nvim_get_current_win()
  local session = H.new()
  local terminal = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(source)
  local data = gents.ready(session.id)
  eq({ data.visible, data.focused, data.win }, { true, false, terminal })
  gents.hide(session.id)
  data = gents.ready(session.id)
  eq({ data.visible, data.focused }, { false, false })
  eq(data.win, nil)
  eq(vim.api.nvim_get_current_win(), source)
  eq(#events("GentsReady"), 2)
end

T["hook ready treats sessions in another tab as hidden"] = function()
  local session = H.new()
  local terminal = vim.api.nvim_get_current_win()
  vim.cmd.tabnew()
  local data = gents.ready(session.id)
  eq({ data.visible, data.focused }, { false, false })
  eq(data.win, nil)
  vim.cmd.tabprevious()
  data = gents.ready(session.id)
  eq({ data.visible, data.focused, data.win }, { true, true, terminal })
  vim.cmd.tabnext()
  data = gents.ready(session.id)
  eq({ data.visible, data.focused }, { false, false })
  eq(data.win, nil)
end

T["hook ready prefers the focused view among current-tab views"] = function()
  local session = H.new()
  vim.cmd.tabnew()
  local source = vim.api.nvim_get_current_win()
  vim.cmd.vsplit()
  local visible = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(visible, session.buf)
  vim.api.nvim_set_current_win(source)
  local data = gents.ready(session.id)
  eq({ data.visible, data.focused, data.win }, { true, false, visible })

  vim.cmd.vsplit()
  local focused = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(focused, session.buf)
  data = gents.ready(session.id)
  eq({ data.visible, data.focused, data.win }, { true, true, focused })
end

T["ready rejects unknown ids without opening a picker"] = function()
  test.expect.error(function()
    gents.ready(-1)
  end, "no session with id")
  eq(observed, {})
end

T["OSC notifications"] = test.new_set({
  parametrize = {
    { "9;done", "focused" },
    { "99;;done", "focused" },
    { "777;notify;Agent;done", "focused" },
    { "9;done", "visible" },
    { "9;done", "hidden" },
    { "9;done", "other-tab" },
  },
}, {
  ---@param payload string
  ---@param visibility "focused"|"visible"|"hidden"|"other-tab"
  ["emit through a real terminal process"] = function(payload, visibility)
    local source = vim.api.nvim_get_current_win()
    local session = H.new({
      cmd = { "sh", "-c", [[read signal; printf '\033]%s\007' "$1"; exec cat]], "sh", payload },
    })
    local terminal = vim.api.nvim_get_current_win()
    if visibility ~= "focused" then
      vim.api.nvim_set_current_win(source)
    end
    if visibility == "hidden" then
      gents.hide(session.id)
    elseif visibility == "other-tab" then
      vim.cmd.tabnew()
    end
    vim.fn.chansend(session.job, "go\n")
    H.wait(function()
      return #events("GentsReady") > 0
    end)
    eq(#events("GentsReady"), 1)
    local data = events("GentsReady")[1].data
    eq(data.id, session.id)
    eq(data.source, "osc")
    local visible = visibility == "focused" or visibility == "visible"
    eq(data.visible, visible)
    eq(data.focused, visibility == "focused")
    eq(data.win, visible and terminal or nil)
  end,
})

T["short-lived notification process emits before exiting"] = function()
  local session = H.new({ cmd = { "sh", "-c", [[printf '\033]9;done\007']] } })
  H.wait(function()
    return session.state == "exited" and #events("GentsReady") > 0
  end)
  eq(#events("GentsReady"), 1)
  eq(events("GentsReady")[1].data.id, session.id)
end

T["progress and notification control sequences are not ready signals"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[
        printf '\033]9;4;1;50\007'
        printf '\033]9;4\007'
        printf '\033]777;preexec\007'
        printf '\033]99;i=1:p=?;\033\\'
        printf '\033]99;i=1:p=alive;\033\\'
        printf '\033]99;i=1:p=close;\033\\'
      ]],
    },
  })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(events("GentsReady"), {})
end

T["multipart OSC 99 emits once when its text notification completes"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[
        printf '\033]99;i=1:d=0;Agent\033\\'
        printf '\033]99;i=1:p=body;done\033\\'
      ]],
    },
  })
  H.wait(function()
    return session.state == "exited" and #events("GentsReady") > 0
  end)
  eq(#events("GentsReady"), 1)
  eq(events("GentsReady")[1].data.id, session.id)
end

T["unrelated terminal sequences and plain terminals do not emit ready"] = function()
  local session = H.new({ cmd = { "sh", "-c", [[printf '\033]133;A\007']] } })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(#events("GentsReady"), 0)
  vim.cmd.enew()
  local job = vim.fn.jobstart({ "sh", "-c", [[printf '\033]9;done\007']] }, { term = true })
  eq(vim.fn.jobwait({ job }, 2000), { 0 })
  eq(#events("GentsReady"), 0)
end

T["a hook inside the session calls ready through Neovim remote-expr"] = function()
  if vim.v.servername == "" then
    local server = vim.fn.serverstart(vim.fn.tempname() .. ".sock")
    test.finally(function()
      vim.fn.serverstop(server)
    end)
  end
  gents.setup({
    tools = {
      hook = {
        cmd = {
          "sh",
          "-c",
          [[exec "$GENTS_TEST_NVIM" --server "$NVIM" --remote-expr "v:lua.require'gents'.ready($GENTS_SESSION)"]],
        },
        env = { GENTS_TEST_NVIM = vim.v.progpath },
      },
    },
  })
  local session = assert(gents.new("hook"))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.exit_code, 0)
  eq(#events("GentsReady"), 1)
  eq(events("GentsReady")[1].data.id, session.id)
  eq(events("GentsReady")[1].data.source, "hook")
end

return T
