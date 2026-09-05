local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local eq = test.expect.equality

---@class agents.test.EventObservation
---@field name string
---@field data agents.SessionEvent|agents.ReadyEvent

---@class agents.test.ReadyObservation: agents.test.EventObservation
---@field data agents.ReadyEvent

---@type agents.test.EventObservation[]
local observed = {}
---@type integer
local group

local function reset()
  ---@type integer[]
  local jobs = {}
  for _, session in ipairs(agents.sessions()) do
    if session.job and session.job > 0 then
      jobs[#jobs + 1] = session.job
    end
  end
  H.reset()
  if #jobs > 0 then
    vim.fn.jobwait(jobs, 2000)
  end
end

---@overload fun(name: "AgentsReady"): agents.test.ReadyObservation[]
---@param name agents.EventName
---@return agents.test.EventObservation[]
local function events(name)
  return vim.tbl_filter(
    ---@param event agents.test.EventObservation
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
      group = vim.api.nvim_create_augroup("AgentsEventsTest", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "Agents*",
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
    { name = "AgentsSessionStart", data = { id = session.id } },
    { name = "AgentsSessionShow", data = { id = session.id, win = first_win } },
  })
  agents.show(session.id)
  eq(#observed, 2)
  vim.cmd.split()
  agents.hide(session.id)
  agents.hide(session.id)
  eq(#events("AgentsSessionHide"), 1)
  agents.show(session.id)
  local shown = events("AgentsSessionShow")
  eq(#shown, 2)
  eq(shown[2].data, { id = session.id, win = vim.api.nvim_get_current_win() })
  agents.close(session.id)
  H.wait(function()
    return #events("AgentsSessionExit") == 1
  end)
  eq(#events("AgentsSessionStart"), 1)
  eq(#events("AgentsSessionShow"), 2)
  eq(#events("AgentsSessionHide"), 2)
  eq(events("AgentsSessionExit")[1].data.id, session.id)
  eq(type(events("AgentsSessionExit")[1].data.exit_code), "number")
end

T["process exit emits its actual exit code and keeps the buffer"] = function()
  local session = H.new({ cmd = { "sh", "-c", "exit 7" } })
  H.wait(function()
    return #events("AgentsSessionExit") == 1
  end)
  eq(events("AgentsSessionExit")[1].data, { id = session.id, exit_code = 7 })
  eq(session.state, "exited")
  eq(agents.sessions(), { session })
  eq(vim.api.nvim_buf_is_valid(session.buf), true)
end

T["a start listener may replace the initial window without a stale show event"] = function()
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AgentsSessionStart",
    callback = function(ev)
      agents.hide(ev.data.id)
      agents.show(ev.data.id, { layout = "tabnew" })
    end,
  })
  local session = H.new()
  eq(events("AgentsSessionShow"), {
    {
      name = "AgentsSessionShow",
      data = { id = session.id, win = vim.api.nvim_get_current_win() },
    },
  })
end

T["successful auto-close emits exit and hides once"] = function()
  agents.setup({ on_exit = "close", tools = { cat = { cmd = { "cat" } } } })
  local session = H.new({ cmd = { "sh", "-c", "exit 0" } })
  H.wait(function()
    return #agents.sessions() == 0
  end)
  eq(events("AgentsSessionExit"), {
    { name = "AgentsSessionExit", data = { id = session.id, exit_code = 0 } },
  })
  eq(#events("AgentsSessionHide"), 1)
  eq(vim.api.nvim_buf_is_valid(session.buf), false)
end

T["failed launches do not emit lifecycle events"] = function()
  test.expect.error(function()
    H.new({ cmd = { "/agents-test-missing-executable" } })
  end)
  eq(observed, {})
  eq(agents.sessions(), {})
end

T["ready signals do not change the send-readiness state"] = function()
  local session = H.new()
  local data = agents.ready(session.id)
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
  eq(events("AgentsReady")[1].data, data)
  eq(session.state, "starting")
end

T["hook ready distinguishes visible and hidden sessions"] = function()
  local source = vim.api.nvim_get_current_win()
  local session = H.new()
  local terminal = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(source)
  local data = agents.ready(session.id)
  eq({ data.visible, data.focused, data.win }, { true, false, terminal })
  agents.hide(session.id)
  data = agents.ready(session.id)
  eq({ data.visible, data.focused }, { false, false })
  eq(data.win, nil)
  eq(vim.api.nvim_get_current_win(), source)
  eq(#events("AgentsReady"), 2)
end

T["ready rejects unknown ids without opening a picker"] = function()
  test.expect.error(function()
    agents.ready(-1)
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
  },
}, {
  ---@param payload string
  ---@param visibility "focused"|"visible"|"hidden"
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
      agents.hide(session.id)
    end
    vim.fn.chansend(session.job, "go\n")
    H.wait(function()
      return #events("AgentsReady") > 0
    end)
    eq(#events("AgentsReady"), 1)
    local data = events("AgentsReady")[1].data
    eq(data.id, session.id)
    eq(data.source, "osc")
    eq(data.visible, visibility ~= "hidden")
    eq(data.focused, visibility == "focused")
    eq(data.win, visibility ~= "hidden" and terminal or nil)
  end,
})

T["short-lived notification process emits before exiting"] = function()
  local session = H.new({ cmd = { "sh", "-c", [[printf '\033]9;done\007']] } })
  H.wait(function()
    return session.state == "exited" and #events("AgentsReady") > 0
  end)
  eq(#events("AgentsReady"), 1)
  eq(events("AgentsReady")[1].data.id, session.id)
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
  eq(events("AgentsReady"), {})
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
    return session.state == "exited" and #events("AgentsReady") > 0
  end)
  eq(#events("AgentsReady"), 1)
  eq(events("AgentsReady")[1].data.id, session.id)
end

T["unrelated terminal sequences and plain terminals do not emit ready"] = function()
  local session = H.new({ cmd = { "sh", "-c", [[printf '\033]133;A\007']] } })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(#events("AgentsReady"), 0)
  vim.cmd.enew()
  local job = vim.fn.jobstart({ "sh", "-c", [[printf '\033]9;done\007']] }, { term = true })
  eq(vim.fn.jobwait({ job }, 2000), { 0 })
  eq(#events("AgentsReady"), 0)
end

T["a hook inside the session calls ready through Neovim remote-expr"] = function()
  if vim.v.servername == "" then
    local server = vim.fn.serverstart(vim.fn.tempname() .. ".sock")
    test.finally(function()
      vim.fn.serverstop(server)
    end)
  end
  agents.setup({
    tools = {
      hook = {
        cmd = {
          "sh",
          "-c",
          [[exec "$AGENTS_TEST_NVIM" --server "$NVIM" --remote-expr "v:lua.require'agents'.ready($AGENTS_SESSION)"]],
        },
        env = { AGENTS_TEST_NVIM = vim.v.progpath },
      },
    },
  })
  local session = assert(agents.new("hook"))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.exit_code, 0)
  eq(#events("AgentsReady"), 1)
  eq(events("AgentsReady")[1].data.id, session.id)
  eq(events("AgentsReady")[1].data.source, "hook")
end

return T
