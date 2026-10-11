local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local status = require("gents.terminal_status")
local protocol = require("gents.status_protocol")
local eq = test.expect.equality
local original_send = vim.api.nvim_ui_send
---@param callback fun(sequence: string)
local function set_send(callback)
  vim.api.nvim_ui_send = callback
end
---@type string[]
local sent
---@type gents.StatusChangedEvent[]
local changes
---@type gents.ReadyEvent[]
local ready
---@type integer
local group

---@param session gents.Session
---@param body string
local function report(session, body)
  status.receive(session, "\027]7501;" .. body)
end

---@param index integer
---@return gents.ProgramReport
local function relayed(index)
  return assert(protocol.parse(sent[index]:sub(1, -3)))
end

---@param enabled boolean
local function setup(enabled)
  gents.setup({ terminal_status = enabled, tools = { cat = { cmd = { "cat" } } } })
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      sent, changes, ready = {}, {}, {}
      set_send(function(sequence)
        sent[#sent + 1] = sequence
      end)
      group = vim.api.nvim_create_augroup("GentsNativeStatusTest", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "GentsStatusChanged",
        callback = function(ev)
          changes[#changes + 1] = vim.deepcopy(ev.data)
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "GentsReady",
        callback = function(ev)
          ready[#ready + 1] = vim.deepcopy(ev.data)
        end,
      })
    end,
    post_case = function()
      vim.api.nvim_del_augroup_by_id(group)
      H.reset()
      set_send(original_send)
    end,
  },
})

T["native events include session metadata and are independent of startup and relay"] = function()
  local session = H.new({ label = "my agent" })
  require("gents.titles").update(session, "Conversation")
  report(session, "state=blocked:kind=permission:title=" .. vim.base64.encode("Worker"))
  eq(ready[1], {
    id = session.id,
    tool = "cat",
    label = "my agent",
    title = "Conversation",
    buf = session.buf,
    win = vim.api.nvim_get_current_win(),
    visible = true,
    focused = true,
    record_id = "",
    current = { state = "blocked", kind = "permission", title = "Worker" },
  })
  eq(changes[1].previous, nil)
  eq(changes[1].current, ready[1].current)
  eq(changes[1].reason, "report")
  eq(session.state, "starting")
  eq(sent, {})
  gents.hide(session.id)
  report(session, "state=blocked:kind=question:msg=" .. vim.base64.encode("Answer?"))
  eq({ ready[2].visible, ready[2].focused }, { false, false })
  eq(ready[2].win, nil)
end

T["ready covers completion, new blocked requests and return to idle after activity"] = function()
  local session = H.new()
  report(session, "state=idle")
  eq(#ready, 0)
  report(session, "state=working:progress=10")
  report(session, "state=idle")
  eq(#ready, 1)
  report(session, "state=idle")
  eq(#changes, 3)
  report(session, "state=done")
  report(session, "state=error")
  eq(#ready, 2)
  report(session, "state=blocked:kind=question:msg=" .. vim.base64.encode("A?"))
  report(
    session,
    "state=blocked:kind=question:msg=" .. vim.base64.encode("A?") .. ":progress=20:title=VGl0bGU="
  )
  eq(#ready, 3)
  report(session, "state=blocked:kind=question:msg=" .. vim.base64.encode("B?"))
  eq(#ready, 4)
  report(session, "state=blocked")
  eq(#ready, 5)
  report(session, "state=clear")
  report(session, "state=idle")
  eq(#ready, 5)
end

T["each new completion fires ready without repeating for metadata updates"] = function()
  local session = H.new()
  report(session, "state=done")
  eq(#ready, 1)
  report(session, "state=done")
  report(session, "state=done:title=VGl0bGU=:msg=UmVzdWx0:app=agent")
  eq(#ready, 1)
  report(session, "state=working")
  report(session, "state=done")
  eq(#ready, 2)
  report(session, "state=done:id=worker")
  eq(#ready, 3)
  eq(ready[3].record_id, "worker")
  eq(#changes, 5)
end

T["native completion reports"] = test.new_set({ parametrize = { { false }, { true } } }, {
  ---@param enabled boolean
  ["emit ready once from a hidden PTY with or without host reporting"] = function(enabled)
    setup(enabled)
    ---@type string[]
    local order = {}
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = { "GentsStatusChanged", "GentsReady" },
      callback = function(ev)
        if ev.data.current then
          order[#order + 1] = ev.match .. ":" .. ev.data.current.state
        end
      end,
    })
    local session = H.new({
      cmd = {
        "sh",
        "-c",
        [[read signal
printf '\033]7501;state=working:app=agent\007'
printf '\033]7501;state=done:app=agent:msg=UmVzdWx0\033\\'
printf '\033]7501;state=done:app=agent:msg=UmVzdWx0\007'
printf '\033]7501;state=done:app=agent:msg=UmVzdWx0:title=VGl0bGU=\007'
printf '\033]2;After completion\007'
exec cat]],
      },
    })
    gents.hide(session.id)
    vim.fn.chansend(session.job, "go\n")
    H.wait(function()
      return session.title == "After completion"
    end)
    eq(order, {
      "GentsStatusChanged:working",
      "GentsStatusChanged:done",
      "GentsReady:done",
      "GentsStatusChanged:done",
    })
    eq(#ready, 1)
    eq(ready[1].id, session.id)
    eq(ready[1].record_id, "")
    eq(ready[1].current, { state = "done", app = "agent", msg = "Result" })
    eq({ ready[1].visible, ready[1].focused }, { false, false })
    eq(changes[2].previous, { state = "working", app = "agent" })
    eq(changes[2].current, ready[1].current)
    if enabled then
      eq(#sent, 3)
      eq(relayed(2).state, "done")
    else
      eq(sent, {})
    end
  end,
})

T["snapshots replace completely and callbacks cannot change stored state"] = function()
  local session = H.new()
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GentsStatusChanged",
    callback = function(ev)
      if ev.data.current then
        ev.data.current.msg = "mutated"
      end
    end,
  })
  report(session, "state=blocked:kind=auth:progress=90:app=agent:msg=SGk=:title=VGl0bGU=")
  report(session, "state=working")
  eq(
    changes[2].previous,
    { state = "blocked", kind = "auth", progress = 90, app = "agent", msg = "Hi", title = "Title" }
  )
  eq(changes[2].current, { state = "working" })
  setup(true)
  eq(relayed(1).msg, nil)
  report(session, "state=working")
  eq(#changes, 2)
  eq(#sent, 1)
end

T["a status listener may close or clear a session without a stale ready event"] = function()
  local session = H.new()
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GentsStatusChanged",
    callback = function(ev)
      if ev.data.current then
        gents.close(session.id)
      end
    end,
  })
  report(session, "state=blocked")
  eq(#ready, 0)
  eq(changes[2].reason, "close")
end

T["hierarchy, inheritance and root clear stay inside their owning session"] = function()
  setup(true)
  local first, second = H.new(), H.new()
  report(first, "state=working:app=agent")
  report(first, "state=blocked:id=worker/a:kind=auth")
  report(second, "state=working:id=worker/a:app=other")
  eq(relayed(2).app, "agent")
  eq(relayed(2).id == relayed(3).id, false)
  report(first, "state=working:app=changed")
  eq(relayed(5).app, "changed")
  report(first, "state=working:id=worker:app=nearest")
  eq(relayed(7).app, "nearest")
  report(first, "state=clear:id=worker")
  eq(changes[#changes - 1].record_id, "worker")
  eq(changes[#changes].record_id, "worker/a")
  eq(changes[#changes].reason, "clear")
  report(first, "state=clear")
  eq(changes[#changes].record_id, "")
  eq(changes[#changes].id, first.id)
  report(second, "state=working:id=worker/a:app=other")
  eq(changes[#changes].id, first.id)
end

T["relay uses legal bounded ids and preserves supplied fields"] = function()
  setup(true)
  local session = H.new()
  local id = table.concat(
    { string.rep("a", 32), string.rep("b", 32), string.rep("c", 32), string.rep("d", 29) },
    "/"
  )
  report(
    session,
    "state=blocked:id="
      .. id
      .. ":kind=permission:progress=0:app=codex:msg=QXBwcm92ZT8:title=V29ya2Vy"
  )
  eq(changes[1].record_id, id)
  local record = relayed(1)
  eq(record, {
    id = "gents/" .. session.id .. "/r1",
    state = "blocked",
    kind = "permission",
    progress = 0,
    app = "codex",
    msg = "Approve?",
    title = "Worker",
  })
  report(session, "state=working:id=" .. id)
  eq(relayed(2), { id = record.id, state = "working" })
end

T["focus and reporting toggles do not acknowledge native records"] = function()
  local origin = vim.api.nvim_get_current_win()
  local session = H.new({ label = "réview\n\127\194\128" })
  report(session, "state=blocked")
  setup(true)
  eq(relayed(1).title, "réview")
  vim.api.nvim_exec_autocmds("FocusLost", { modeline = false })
  vim.api.nvim_set_current_win(origin)
  gents.show(session.id)
  vim.api.nvim_exec_autocmds("FocusGained", { modeline = false })
  eq(#sent, 1)
  setup(false)
  eq(relayed(2), { id = "gents/" .. session.id, state = "clear" })
  setup(true)
  eq(relayed(3).state, "blocked")
  eq(#changes, 1)
  eq(#ready, 1)
end

T["prompt and process exit preserve done/error children when live parents disappear"] = function()
  setup(true)
  local session = H.new({ cmd = { "sh", "-c", "read signal; exit 7" } })
  report(session, "state=working:app=agent")
  report(session, "state=done:id=worker")
  report(session, "state=error:id=failed")
  report(session, "state=blocked:id=waiting")
  vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = session.buf,
    data = { sequence = "\027]133;A", terminator = "\007", cursor = { 1, 0 } },
  })
  eq(changes[#changes].reason, "prompt")
  eq(relayed(#sent).state, "clear")
  report(session, "state=working")
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return session.state == "exited"
  end)
  eq(changes[#changes].reason, "exit")
  eq(changes[#changes].record_id, "")
  local count = #changes
  report(session, "state=blocked")
  eq(#changes, count)
  setup(false)
  setup(true)
  eq(relayed(#sent - 1).state, "error")
  eq(relayed(#sent).state, "done")
  gents.close(session.id)
  eq(changes[#changes].reason, "close")
  eq(relayed(#sent), { id = "gents/" .. session.id, state = "clear" })
end

T["buffer removal and shutdown clear owned records"] = function()
  setup(true)
  local first = H.new()
  report(first, "state=done")
  vim.api.nvim_buf_delete(first.buf, { force = true })
  eq(changes[2].reason, "buffer")
  eq(relayed(2), { id = "gents/" .. first.id, state = "clear" })
  local second = H.new()
  report(second, "state=error")
  vim.api.nvim_exec_autocmds("VimLeavePre", { modeline = false })
  eq(changes[4].reason, "shutdown")
  eq(relayed(4), { id = "gents/" .. second.id, state = "clear" })
end

T["record cap evicts the least recently updated record without clearing its descendants"] = function()
  local session = H.new()
  report(session, "state=done:id=parent")
  report(session, "state=done:id=parent/child")
  for i = 3, 256 do
    report(session, "state=done:id=r" .. i)
  end
  report(session, "state=done:id=parent/child")
  eq(#changes, 256)
  report(session, "state=done:id=new")
  eq(changes[257].record_id, "parent")
  eq(changes[257].reason, "evicted")
  eq(changes[258].record_id, "new")
  report(session, "state=clear:id=parent")
  eq(changes[259].record_id, "parent/child")
end

T["invalid reports and old notification protocols do not provide status features"] = function()
  setup(true)
  local session = H.new()
  for _, sequence in ipairs({
    "\027]7501;state=blocked:id=bad//id",
    "\027]7501;state=done:msg=Cg==",
    "\027]9;done",
    "\027]99;d=1;done",
    "\027]777;notify;title;done",
    "\027]9;4;1;50",
    "\007",
    "\027]2;Title",
  }) do
    vim.api.nvim_exec_autocmds(
      "TermRequest",
      { buffer = session.buf, data = { sequence = sequence } }
    )
  end
  eq(changes, {})
  eq(ready, {})
  eq(sent, {})
end

T["real PTY reports survive chunks and hidden buffers with both terminators"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[read signal; printf '\033]7501;state=wor'; sleep 0.05; printf 'king\007\033]7501;state=blocked:id=worker:kind=auth\033\\'; exec cat]],
    },
  })
  gents.hide(session.id)
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return #changes == 2
  end)
  eq(changes[1].current, { state = "working" })
  eq(changes[2].record_id, "worker")
  eq(ready[1].current, { state = "blocked", kind = "auth" })
  eq(ready[1].visible, false)
end

T["a short-lived native producer leaves its final result"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[printf '\033]7501;state=working\007\033]7501;state=done:msg=UmVzdWx0\033\\'; exit 0]],
    },
  })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(#changes, 2)
  eq(#ready, 1)
  eq(ready[1].current, { state = "done", msg = "Result" })
  setup(true)
  eq(relayed(1).state, "done")
  eq(relayed(1).msg, "Result")
end

T["soft reset and alternate-screen switches preserve native records"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[printf '\033]7501;state=working\007'; read signal; printf '\033[!p\033[?1049h\033[?1049l\033]7501;state=working\007\033]2;After reset\007'; exec cat]],
    },
  })
  H.wait(function()
    return #changes == 1
  end)
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return session.title == "After reset"
  end)
  eq(#changes, 1)
  setup(true)
  eq(relayed(1).state, "working")
end

T["real capability replies go to the exact child PTY even with relay disabled"] = function()
  local session = H.new({
    cmd = {
      "python3",
      "-c",
      [[import os, select, tty
tty.setraw(0)
os.write(1, b'\x1b]7501;?\x1b\\')
reply = b''
while len(reply) < 10:
    if not select.select([0], [], [], 2)[0]: raise SystemExit(2)
    reply += os.read(0, 64)
os.write(1, b'\x1b]7501;state=done\x07' if reply == b'\x1b]7501;?\x1b\\' else b'\x1b]7501;state=error\x07')
]],
    },
  })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.exit_code, 0)
  eq(changes[1].current, { state = "done" })
  eq(#ready, 1)
  eq(ready[1].current, { state = "done" })
  eq(sent, {})
end

T["capability reply precedes the primary device attributes fallback"] = function()
  local session = H.new({
    cmd = {
      "python3",
      "-c",
      [[import os, select, tty
tty.setraw(0)
os.write(1, b'\x1b]7501;?\x1b\\\x1b[c')
if not select.select([0], [], [], 2)[0]: raise SystemExit(2)
reply = os.read(0, 256)
raise SystemExit(0 if reply.startswith(b'\x1b]7501;?\x1b\\') else 3)
]],
    },
  })
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.exit_code, 0)
  eq(changes, {})
  eq(sent, {})
end

return T
