local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local send = require("gents.send")
local eq = test.expect.equality

---@type string[]
local files = {}
---@type gents.SendEvent[]
local observed = {}
---@type integer
local group

local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      observed = {}
      group = vim.api.nvim_create_augroup("GentsSendTest", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "GentsSend",
        callback = function(ev)
          observed[#observed + 1] = vim.deepcopy(ev.data)
        end,
      })
    end,
    post_case = function()
      vim.api.nvim_del_augroup_by_id(group)
      H.reset()
      for _, file in ipairs(files) do
        vim.fn.delete(file)
      end
      files = {}
    end,
  },
})

-- A real PTY application enables bracketed paste, then records every input byte.
-- Raw mode keeps the kernel from turning carriage returns into line feeds.
---@param banner? boolean
---@return gents.test.Session, string
local function receiver(banner)
  local path = vim.fn.tempname()
  files[#files + 1] = path
  local greeting = banner == false and ""
    or "one\\r\\ntwo\\r\\nthree\\r\\nfour\\r\\nfive\\r\\nsix\\r\\n"
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      "stty raw -echo; printf '\\033[?2004h" .. greeting .. '\'; exec cat > "$1"',
      "gents-send-test",
      path,
    },
  })
  return session, path
end

---@param path string
---@return string
local function received(path)
  if vim.fn.filereadable(path) == 0 then
    return ""
  end
  return table.concat(vim.fn.readfile(path, "b"), "\n")
end

---@param text string
---@return string
local function paste(text)
  return "\027[200~" .. text .. "\027[201~"
end

T["queued multiline paste preserves line breaks without an Enter keystroke"] = function()
  local session, path = receiver()
  send.enqueue(session, "first\r\nsecond")
  eq(session.state, "starting")
  eq(observed, {})
  H.wait(function()
    return received(path) ~= "" and #observed == 1
  end)
  eq(session.state, "ready")
  eq(received(path), paste("first\nsecond\n"))
  eq(observed, { { id = session.id, submit = false } })
end

T["submit sends exactly one separate CR and preserves message order"] = function()
  local session, path = receiver()
  send.enqueue(session, "first", true)
  send.enqueue(session, "second\n")
  local expected = paste("first\n") .. "\r" .. paste("second\n")
  H.wait(function()
    return received(path) == expected and #observed == 2
  end)
  eq(observed, { { id = session.id, submit = true }, { id = session.id, submit = false } })
end

T["delivery to a hidden buffer preserves the current window and cursor"] = function()
  local source = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_win_set_cursor(source, { 2, 1 })
  local session, path = receiver()
  gents.hide(session.id)
  vim.api.nvim_set_current_win(source)
  vim.cmd.stopinsert()
  send.enqueue(session, "hidden")
  H.wait(function()
    return received(path) ~= "" and #observed == 1
  end)
  eq(vim.api.nvim_get_current_win(), source)
  eq(vim.api.nvim_win_get_cursor(source), { 2, 1 })
  eq(vim.fn.win_findbuf(session.buf), {})
  eq(received(path), paste("hidden\n"))
end

T["quiet jobs become ready after five seconds and drain queued input"] = function()
  local started = vim.uv.hrtime()
  local session, path = receiver(false)
  send.enqueue(session, "quiet")
  eq(
    vim.wait(4500, function()
      return session.state == "ready"
    end, 20),
    false
  )
  eq(received(path), "")
  H.wait(function()
    return received(path) ~= "" and #observed == 1
  end)
  eq((vim.uv.hrtime() - started) / 1e6 >= 5000, true)
  eq(received(path), paste("quiet\n"))
end

T["ready sessions resume an idle queue for later sends"] = function()
  local session, path = receiver()
  send.enqueue(session, "first")
  H.wait(function()
    return received(path) == paste("first\n")
  end)
  -- Allow the queue to become idle before sending a second message.
  vim.wait(250, function()
    return false
  end, 10)
  send.enqueue(session, "later", true)
  H.wait(function()
    return received(path) == paste("first\n") .. paste("later\n") .. "\r"
  end)
  eq(#observed, 2)
end

T["startup output must remain unchanged for half a second"] = function()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      "printf 'one\\ntwo\\nthree\\nfour\\nfive\\nsix\\n'; sleep 0.3; printf 'last\\n'; exec cat",
    },
  })
  H.wait(function()
    return table
      .concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
      :find("last", 1, true) ~= nil
  end)
  local changed = vim.uv.hrtime()
  H.wait(function()
    return session.state == "ready"
  end)
  eq((vim.uv.hrtime() - changed) / 1e6 >= 500, true)
end

T["closing or wiping a starting session discards queued input"] = function()
  local closed, closed_path = receiver()
  local wiped, wiped_path = receiver()
  send.enqueue(closed, "closed", true)
  send.enqueue(wiped, "wiped", true)
  gents.close(closed.id)
  vim.api.nvim_buf_delete(wiped.buf, { force = true })
  H.wait(function()
    return closed.state == "exited" and wiped.state == "exited"
  end)
  eq(received(closed_path), "")
  eq(received(wiped_path), "")
  eq(observed, {})
  test.expect.error(function()
    send.enqueue(closed, "late")
  end, "exited or closed session")
  test.expect.error(function()
    send.enqueue(wiped, "late")
  end, "exited or closed session")
end

T["natural exit discards queued input and leaves the transcript readable"] = function()
  local session = H.new({ cmd = { "sh", "-c", "printf finished; exit 0" } })
  send.enqueue(session, "late", true)
  H.wait(function()
    return session.state == "exited"
  end)
  eq(observed, {})
  eq(vim.api.nvim_buf_is_valid(session.buf), true)
  test.expect.error(function()
    send.enqueue(session, "later")
  end, "exited or closed session")
end

T["a send listener can close during a large paste before its pending submit"] = function()
  local session, path = receiver()
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GentsSend",
    callback = function()
      gents.close(session.id)
    end,
  })
  send.enqueue(session, string.rep("closing", 150000), true)
  H.wait(function()
    return session.state == "exited" and not vim.api.nvim_buf_is_valid(session.buf)
  end)
  -- Closing may beat the child process reading its PTY, but must never send Enter.
  eq(received(path):find("\r", 1, true), nil)
  eq(observed, { { id = session.id, submit = true } })
end

return T
