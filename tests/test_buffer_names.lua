local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

---@param buflisted? boolean
local function setup(buflisted)
  gents.setup({
    buflisted = buflisted or false,
    tools = {
      cat = {
        cmd = { "cat" },
        title = function(title)
          return title ~= "reset" and title or nil
        end,
      },
    },
  })
end

---@param session gents.Session
---@param title string
local function update(session, title)
  -- Exercise the title event path with a live terminal; OSC transport has its
  -- own real-output coverage in test_titles.lua.
  vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = session.buf,
    data = { sequence = "\027]2;" .. title, terminator = "\007", cursor = { 1, 0 } },
  })
end

---@param session gents.Session
---@param display string
---@return string
local function name(session, display)
  return "gents://" .. session.id .. "/" .. display
end

---@return string[]
local function terminal_names()
  ---@type string[]
  local names = {}
  -- Include unloaded buffers: renaming can leave aliases outside the buffer list.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local value = vim.api.nvim_buf_get_name(buf)
      if value:match("^gents://") or value:match("^term://") then
        names[#names + 1] = value
      end
    end
  end
  table.sort(names)
  return names
end

T["buffer listing and naming"] = test.new_set({
  parametrize = { { false }, { true } },
}, {
  ---@param buflisted boolean
  ["are independent and preserve the live terminal"] = function(buflisted)
    setup(buflisted)
    local session = H.new({ label = "Review changes" })
    local buf, job = session.buf, session.job
    eq(vim.api.nvim_buf_get_name(buf), name(session, "Review changes"))
    update(session, "Inspect tests")
    eq(vim.api.nvim_buf_get_name(buf), name(session, "cat · Inspect tests"))
    eq(session.title, "Inspect tests")
    eq(session.label, "Review changes")
    eq({ session.buf, session.job }, { buf, job })
    eq(vim.bo[buf].channel, job)
    eq(vim.bo[buf].buflisted, buflisted)
    eq(vim.bo[buf].buftype, "terminal")
    eq(vim.bo[buf].filetype, "gents_terminal")
    eq(vim.fn.jobwait({ job }, 0), { -1 })
    vim.fn.chansend(job, "still-alive-after-rename\n")
    H.wait(function()
      return table
        .concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        :find("still-alive-after-rename", 1, true) ~= nil
    end)
    eq(terminal_names(), { vim.api.nvim_buf_get_name(buf) })
  end,
})

T["all sessions receive useful names without any naming configuration"] = function()
  local first, second = H.new(), H.new()
  eq(vim.api.nvim_buf_get_name(first.buf), name(first, "cat"))
  eq(vim.api.nvim_buf_get_name(second.buf), name(second, "cat #2"))
  update(first, "Default naming")
  eq(vim.api.nvim_buf_get_name(first.buf), name(first, "cat · Default naming"))
end

T["hidden renames and resets preserve focus, cursor, and the alternate buffer"] = function()
  setup()
  local session = H.new({ label = "Custom label" })
  gents.hide(session.id)
  local alternate = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(alternate, vim.fn.tempname())
  vim.cmd.enew()
  local current, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(current, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_win_set_cursor(win, { 2, 1 })
  eq(vim.fn.bufnr("#"), alternate)
  local cursor, mode = vim.api.nvim_win_get_cursor(win), vim.api.nvim_get_mode().mode
  for _, title in ipairs({ "First title", "Second title", "reset", "Resumed title" }) do
    update(session, title)
    local display = title == "reset" and "Custom label" or "cat · " .. title
    eq(vim.api.nvim_buf_get_name(session.buf), name(session, display))
    eq(terminal_names(), { name(session, display) })
    eq(vim.api.nvim_get_current_win(), win)
    eq(vim.api.nvim_get_current_buf(), current)
    eq(vim.fn.bufnr("#"), alternate)
    eq(vim.api.nvim_win_get_cursor(win), cursor)
    eq(vim.api.nvim_get_mode().mode, mode)
    eq(vim.fn.win_findbuf(session.buf), {})
  end
end

T["matching titles remain unique by session id"] = function()
  setup()
  local first, second = H.new(), H.new()
  update(first, "Shared title")
  update(second, "Shared title")
  local expected = { name(first, "cat · Shared title"), name(second, "cat · Shared title") }
  table.sort(expected)
  eq(terminal_names(), expected)
  eq(vim.api.nvim_buf_get_name(first.buf) ~= vim.api.nvim_buf_get_name(second.buf), true)
  eq(vim.fn.jobwait({ first.job, second.job }, 0), { -1, -1 })
end

T["names sanitize path separators and controls while retaining full title metadata"] = function()
  setup()
  local label = "  review/branch\\work\t\n\0 café 日本語  "
  local session = H.new({ label = label })
  eq(vim.api.nvim_buf_get_name(session.buf), name(session, "review branch work café 日本語"))
  eq(session.label, label)
  local title = [[Inspect src/main.lua\tests  · café 日本語 🔍 % # | "quotes"]]
  update(session, title)
  eq(
    vim.api.nvim_buf_get_name(session.buf),
    name(session, [[cat · Inspect src main.lua tests · café 日本語 🔍 % # | "quotes"]])
  )
  eq(session.title, title)
  eq(gents.status()[1].title, title)
  update(session, "reset")
  eq(session.title, nil)
  eq(vim.api.nvim_buf_get_name(session.buf), name(session, "review branch work café 日本語"))
end

T["empty sanitized names fall back to the session label then tool name"] = function()
  setup()
  local session = H.new({ label = " /\\\t " })
  eq(vim.api.nvim_buf_get_name(session.buf), name(session, "cat"))
  update(session, "/\\")
  eq(session.title, "/\\")
  eq(vim.api.nvim_buf_get_name(session.buf), name(session, "cat"))
end

T["real OSC output renames a hidden terminal without leaving buffer aliases"] = function()
  setup()
  local session = H.new({
    cmd = {
      "sh",
      "-c",
      [[while IFS= read -r title; do printf '\033]2;%s\007' "$title"; done]],
    },
  })
  gents.hide(session.id)
  local current, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  for _, title in ipairs({ "First real title", "Renamed real title", "reset" }) do
    vim.fn.chansend(session.job, title .. "\n")
    local expected = name(session, title == "reset" and "cat" or "cat · " .. title)
    H.wait(function()
      return vim.api.nvim_buf_get_name(session.buf) == expected
    end)
    eq(terminal_names(), { expected })
    eq(vim.api.nvim_get_current_buf(), current)
    eq(vim.api.nvim_get_current_win(), win)
    eq(vim.fn.win_findbuf(session.buf), {})
    eq(vim.fn.jobwait({ session.job }, 0), { -1 })
  end
end

T["rename cleanup preserves unrelated loaded and unloaded buffers"] = function()
  setup()
  local unrelated = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(unrelated, "gents://unrelated/Notes")
  vim.api.nvim_buf_set_lines(unrelated, 0, -1, false, { "Keep these notes" })
  local unloaded = vim.fn.bufadd("term://unrelated")
  eq(vim.api.nvim_buf_is_loaded(unloaded), false)
  local session = H.new()
  update(session, "First title")
  update(session, "Second title")
  update(session, "reset")
  eq(vim.api.nvim_buf_is_valid(unrelated), true)
  eq(vim.api.nvim_buf_get_lines(unrelated, 0, -1, false), { "Keep these notes" })
  eq(vim.bo[unrelated].modified, true)
  eq(vim.api.nvim_buf_is_valid(unloaded), true)
  eq(vim.api.nvim_buf_is_loaded(unloaded), false)
  local expected = { name(session, "cat"), "gents://unrelated/Notes", "term://unrelated" }
  table.sort(expected)
  eq(terminal_names(), expected)
end

T["session removal"] = test.new_set({ parametrize = { { "close" }, { "delete" } } }, {
  ---@param action string
  ["leaves no old names or recreated session buffer"] = function(action)
    setup(true)
    local session = H.new()
    update(session, "First title")
    update(session, "Second title")
    if action == "close" then
      gents.close(session.id)
      require("gents.titles").update(session, "Late title")
    else
      vim.cmd.bdelete({ args = { tostring(session.buf) }, bang = true })
    end
    H.wait(function()
      return session.state == "exited" and not vim.api.nvim_buf_is_valid(session.buf)
    end)
    require("gents.titles").update(session, "Even later title")
    eq(gents.sessions(), {})
    eq(terminal_names(), {})
    eq(vim.fn.jobwait({ session.job }, 0)[1] ~= -1, true)
  end,
})

return T
