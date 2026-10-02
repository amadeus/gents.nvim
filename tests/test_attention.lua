local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality
local original_send = vim.api.nvim_ui_send
---@type string[]
local sent = {}

---@param callback fun(content: string)
local function set_send(callback)
  vim.api.nvim_ui_send = callback
end

---@param event string
local function focus(event)
  vim.api.nvim_exec_autocmds(event, { modeline = false })
end

---@param enabled boolean
local function setup(enabled)
  gents.setup({ terminal_status = enabled, tools = { cat = { cmd = { "cat" } } } })
end

---@param session gents.Session
---@return string
local function blocked(session)
  return "\027]7501;state=blocked:id=gents/"
    .. session.id
    .. ":app=gents:title="
    .. vim.base64.encode(session.label)
    .. ":msg="
    .. vim.base64.encode("Session needs attention")
    .. "\027\\"
end

---@param id integer
---@return string
local function clear(id)
  return "\027]7501;state=clear:id=gents/" .. id .. "\027\\"
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      focus("FocusGained")
      sent = {}
      ---@param sequence string
      set_send(function(sequence)
        sent[#sent + 1] = sequence
      end)
    end,
    post_case = function()
      H.reset()
      focus("FocusGained")
      set_send(original_send)
    end,
  },
})

T["attention is tracked without terminal reporting and preserves startup state"] = function()
  local source = vim.api.nvim_get_current_win()
  local session = H.new()
  eq(session.attention, false)
  gents.ready(session.id)
  eq(session.attention, false)
  vim.api.nvim_set_current_win(source)
  local data = gents.ready(session.id)
  eq({ data.visible, data.focused }, { true, false })
  eq(session.attention, true)
  eq(gents.status()[1].attention, true)
  eq(session.state, "starting")
  eq(sent, {})
  gents.show(session.id)
  eq(session.attention, false)
end

T["background ready remains pending through native navigation until focus returns"] = function()
  setup(true)
  local source = vim.api.nvim_get_current_win()
  local session = H.new()
  local terminal = vim.api.nvim_get_current_win()
  focus("FocusLost")
  eq(gents.ready(session.id).focused, true)
  eq(session.attention, true)
  eq(sent, { blocked(session) })
  vim.api.nvim_set_current_win(source)
  vim.api.nvim_set_current_win(terminal)
  eq(sent, { blocked(session) })
  eq(session.attention, true)
  focus("FocusGained")
  eq(session.attention, false)
  eq(sent, { blocked(session), clear(session.id) })
end

T["returning to the editor preserves other sessions until each is focused"] = function()
  setup(true)
  local source = vim.api.nvim_get_current_win()
  local first = H.new()
  local first_win = vim.api.nvim_get_current_win()
  local second = H.new()
  local second_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(source)
  gents.ready(first.id)
  gents.ready(second.id)
  eq(sent, { blocked(first), blocked(second) })
  focus("FocusLost")
  focus("FocusGained")
  eq({ first.attention, second.attention }, { true, true })
  eq(#sent, 2)
  vim.api.nvim_set_current_win(first_win)
  eq({ first.attention, second.attention }, { false, true })
  eq(sent[3], clear(first.id))
  vim.api.nvim_set_current_win(second_win)
  eq(second.attention, false)
  eq(sent[4], clear(second.id))
end

T["native buffer and tab navigation acknowledges the selected session"] = function()
  setup(true)
  local session = H.new()
  local terminal_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  gents.ready(session.id)
  eq(session.attention, true)
  vim.api.nvim_set_current_tabpage(terminal_tab)
  eq(session.attention, false)
  eq(sent[2], clear(session.id))
  vim.cmd.enew()
  gents.ready(session.id)
  vim.api.nvim_set_current_buf(session.buf)
  eq(session.attention, false)
  eq(sent[4], clear(session.id))
end

T["hidden sessions report blocked and focused sessions do not"] = function()
  setup(true)
  local session = H.new()
  gents.ready(session.id)
  eq(sent, {})
  gents.hide(session.id)
  eq(gents.ready(session.id).visible, false)
  eq(sent, { blocked(session) })
end

T["real OSC notifications use the same attention tracking"] = function()
  setup(true)
  local session = H.new({
    cmd = { "sh", "-c", [[read signal; printf '\033]9;done\007'; exec cat]] },
  })
  gents.hide(session.id)
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return session.attention
  end)
  eq(sent, { blocked(session) })
end

T["exit clears attention before exit listeners and ignores later ready signals"] = function()
  setup(true)
  local session = H.new({ cmd = { "sh", "-c", "read signal; exit 7" } })
  gents.hide(session.id)
  gents.ready(session.id)
  local group = vim.api.nvim_create_augroup("GentsAttentionExitTest", { clear = true })
  test.finally(function()
    vim.api.nvim_del_augroup_by_id(group)
  end)
  local observed = false
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GentsSessionExit",
    callback = function()
      observed = true
      eq(session.attention, false)
      eq(sent[2], clear(session.id))
    end,
  })
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return observed
  end)
  gents.ready(session.id)
  eq(session.attention, false)
  eq(#sent, 2)
end

T["closing a session clears its record immediately"] = function()
  setup(true)
  local session = H.new()
  gents.hide(session.id)
  gents.ready(session.id)
  gents.close(session.id)
  eq(session.attention, false)
  eq(sent, { blocked(session), clear(session.id) })
end

T["native buffer removal clears the session record"] = function()
  setup(true)
  local session = H.new()
  gents.hide(session.id)
  gents.ready(session.id)
  vim.api.nvim_buf_delete(session.buf, { force = true })
  eq(session.attention, false)
  eq(sent, { blocked(session), clear(session.id) })
end

T["reporting can be toggled without losing pending attention or outer focus"] = function()
  local session = H.new()
  focus("FocusLost")
  gents.ready(session.id)
  eq(sent, {})
  setup(true)
  eq(sent, { blocked(session) })
  setup(true)
  eq(#sent, 1)
  setup(false)
  eq(sent[2], "\027]7501;state=clear:id=gents\027\\")
  eq(session.attention, true)
  setup(true)
  eq(sent[3], blocked(session))
  gents.ready(session.id)
  eq(session.attention, true)
  focus("FocusGained")
  eq(sent[5], clear(session.id))
end

T["Neovim exit clears only the gents record subtree"] = function()
  setup(true)
  local session = H.new()
  gents.hide(session.id)
  gents.ready(session.id)
  focus("VimLeavePre")
  eq(sent[2], "\027]7501;state=clear:id=gents\027\\")
end

T["report titles remove protocol control characters and preserve UTF-8"] = function()
  setup(true)
  local session = H.new({ label = "réview\n\127\194\128" })
  gents.hide(session.id)
  gents.ready(session.id)
  local title = assert(sent[1]:match(":title=([^:]+)"))
  eq(vim.base64.decode(title), "réview")
end

T["oversized labels omit the optional title without losing the report"] = function()
  setup(true)
  local session = H.new({ label = string.rep("é", 97) })
  gents.hide(session.id)
  gents.ready(session.id)
  eq(sent[1]:find(":title=", 1, true), nil)
  eq(sent[1]:sub(1, 7), "\027]7501;")
  eq(sent[1]:match("state=blocked:id=gents/" .. session.id) ~= nil, true)
end

return T
