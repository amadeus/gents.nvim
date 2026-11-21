local test = require("mini.test")
local eq = test.expect.equality
local H = require("tests.helpers")
local gents = require("gents")
local update = require("gents.titles").update
---@type string
local dir
---@type string?, string?, string?, string?
local path, session_id, block_id, parent_nvim

-- A real executable exercises argv boundaries and delayed writes. Log before
-- applying a rename so a test can switch owners while the command is running.
local fake = [=[#!/bin/sh
cd "${0%/*}" || exit 1
[ "$1 $2 $4 $5" = "--autostart=false block -s test-session" ] || exit 2
echo "$3" >> calls
if [ -f "$3-once" ]; then
  mv "$3-once" "$3-failed"
  exit 1
fi
case "$3" in
  inspect)
    [ "$6 $7 $8" = "--json -- test-block" ] || exit 2
    [ ! -f fail ] || { touch failed; exit 1; }
    cat label.json ;;
  rename)
    [ "$6 $7" = "-- test-block" ] && [ "$#" -eq 8 ] || exit 2
    printf '%s\n' "$8" >> writes
    [ ! -f delay ] || sleep 0.1
    [ ! -f reject ] || { touch rejected; exit 1; }
    # Test labels can include shell syntax but never JSON quotes or backslashes.
    printf '{"block":{"label":"%s"}}\n' "$8" > label.tmp
    mv label.tmp label.json ;;
esac]=]

---@param label string
local function external(label)
  vim.fn.writefile({ vim.json.encode({ block = { label = label } }) }, dir .. "/label.json")
end

---@param name string
---@return string[]
local function lines(name)
  local file = dir .. "/" .. name
  return vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or {}
end

---@param label string
local function wait_label(label)
  H.wait(function()
    local data = vim.json.decode(lines("label.json")[1])
    return data.block.label == label
  end)
end

---@param enabled boolean
local function setup(enabled)
  gents.setup({ rex_pane_title = enabled, tools = { cat = { cmd = { "cat" } } } })
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      H.reset()
      dir = vim.fn.tempname()
      vim.fn.mkdir(dir)
      vim.fn.writefile(vim.split(fake, "\n", { plain = true }), dir .. "/rex")
      vim.fn.setfperm(dir .. "/rex", "rwx------")
      path, session_id, block_id = vim.env.PATH, vim.env.REX_SESSION, vim.env.REX_BLOCK
      parent_nvim = vim.env.NVIM
      vim.env.NVIM = nil
      vim.env.PATH = dir .. ":" .. assert(path)
      vim.env.REX_SESSION, vim.env.REX_BLOCK = "test-session", "test-block"
      external("Editor")
    end,
    post_case = function()
      setup(false)
      if vim.fn.exists("#gents_rex_pane_title#VimLeavePre") == 1 then
        vim.api.nvim_exec_autocmds("VimLeavePre", { group = "gents_rex_pane_title" })
      end
      H.reset()
      vim.env.PATH, vim.env.REX_SESSION, vim.env.REX_BLOCK = path, session_id, block_id
      vim.env.NVIM = parent_nvim
      vim.fn.delete(dir, "rf")
    end,
  },
})

T["oldest live session owns the pane even while hidden or untitled"] = function()
  setup(true)
  local first, second = H.new(), H.new()
  update(second, "Review")
  gents.hide(first.id)
  eq(lines("calls"), {})
  update(first, "Fix")
  wait_label("Fix")
  update(second, "Review tests")
  vim.fn.jobstop(first.job)
  wait_label("Review tests")
  eq(first.state, "exited")
  eq(vim.api.nvim_buf_is_valid(first.buf), true)
  gents.close(second.id)
  wait_label("Editor")
  eq(lines("writes"), { "Fix", "Review tests", "Editor" })
end

T["manual selection follows the chosen session until reset or exit"] = function()
  setup(true)
  local first, second = H.new(), H.new({ label = "code review" })
  update(first, "Fix")
  update(second, "Review")
  wait_label("Fix")
  gents.focus(first.id)
  vim.cmd("Gents actions rex-title code review")
  wait_label("Review")
  eq(gents.current(), first)
  update(first, "Latest fix")
  update(second, second.cwd)
  wait_label("Editor")
  update(second, "Review tests")
  wait_label("Review tests")
  vim.cmd("Gents rex-title --reset")
  wait_label("Latest fix")
  eq(gents.rex_title(second.id), second)
  wait_label("Review tests")
  vim.fn.jobstop(second.job)
  wait_label("Latest fix")
  eq(gents.rex_title(second.id), nil)
  gents.close(first.id)
  wait_label("Editor")
end

T["explicit selection reclaims a manually renamed pane and restores the latest label"] = function()
  setup(true)
  local first = H.new()
  update(first, "Review")
  wait_label("Review")
  external("Build")
  vim.cmd("Gents rex-title " .. first.id)
  wait_label("Review")
  external("Tests")
  vim.cmd("Gents rex-title --reset")
  wait_label("Review")
  gents.close(first.id)
  wait_label("Tests")
  eq(lines("writes"), { "Review", "Review", "Review", "Tests" })
end

T["only the exact --reset argument resets Rex title selection"] = function()
  setup(true)
  local first, second = H.new({ label = "--reset" }), H.new({ label = "--reset review" })
  update(first, "First")
  update(second, "Second")
  wait_label("First")
  local prefix = "Gents rex-title "
  local complete = require("gents.commands").complete
  local line = prefix .. "--reset"
  eq(complete("--reset", line, #line), { "--reset review", "--reset" })
  line = line .. " rev"
  eq(complete("rev", line, #line), { "review" })
  vim.cmd(prefix .. "--reset review")
  wait_label("Second")
  vim.cmd(prefix .. "--reset")
  wait_label("First")
end

T["Rex title picker selects from running sessions and tolerates a stale choice"] = function()
  setup(true)
  local first, second, exited = H.new(), H.new(), H.new()
  vim.fn.jobstop(exited.job)
  H.wait(function()
    return exited.state == "exited"
  end)
  update(first, "First")
  update(second, "Second")
  wait_label("First")
  gents.focus(first.id)
  ---@type gents.PickerSpec<gents.Session>?
  local picker
  require("gents.config").get().picker = function(spec)
    picker = spec
  end
  vim.cmd("Gents rex-title")
  local spec = assert(picker)
  eq(spec.title, "Gents: Rex pane title")
  eq(#spec.items, 2)
  eq(vim.tbl_keys(spec.actions), { "select" })
  local item = spec.items[1].data == second and spec.items[1] or spec.items[2]
  eq(item.data, second)
  spec.actions[spec.default](item)
  wait_label("Second")
  eq(gents.current(), first)
  vim.cmd("Gents rex-title")
  spec = assert(picker)
  vim.fn.jobstop(second.job)
  wait_label("First")
  spec.actions[spec.default](item)
  update(first, "Still first")
  wait_label("Still first")
end

T["rex_title rejects a predicate before evaluating it or opening a picker"] = function()
  setup(true)
  H.new()
  H.new()
  gents.hide(nil, { all = true })
  require("gents.config").get().picker = function()
    error("unexpected picker")
  end
  local evaluated = false
  local function predicate()
    evaluated = true
    return true
  end
  test.expect.error(function()
    ---@diagnostic disable-next-line: param-type-mismatch
    gents.rex_title(predicate)
  end, "rex_title expects a session ID, a label, or false to reset")
  eq(evaluated, false)
end

T["turning off automatic titles restores the label and forgets the override"] = function()
  setup(true)
  local first, second = H.new(), H.new()
  update(first, "First")
  update(second, "Second")
  vim.cmd("Gents rex-title " .. second.id)
  wait_label("Second")
  setup(false)
  wait_label("Editor")
  setup(true)
  wait_label("First")
end

T["manual opt-in follows one session until it ends"] = test.new_set({
  parametrize = { { "exit" }, { "close" }, { "reset" } },
}, {
  ---@param ending string
  ["restores the pane and leaves other sessions alone"] = function(ending)
    setup(false)
    local first, second = H.new(), H.new({ label = "review" })
    update(first, "First")
    update(second, "Second")
    eq(lines("calls"), {})
    vim.cmd("Gents rex-title review")
    wait_label("Second")
    update(second, "Second update")
    wait_label("Second update")
    if ending == "exit" then
      vim.fn.jobstop(second.job)
    elseif ending == "close" then
      gents.close(second.id)
    else
      vim.cmd("Gents rex-title --reset")
    end
    wait_label("Editor")
    local calls = lines("calls")
    update(first, "First update")
    update(H.new(), "Third")
    eq(lines("calls"), calls)
    eq(lines("writes"), { "Second", "Second update", "Editor" })
    eq(gents.rex_title(first.id), first)
    wait_label("First update")
  end,
})

T["the actions picker offers a session opt-in with automatic titles off"] = function()
  setup(false)
  local session = H.new()
  update(session, "Planning")
  ---@type gents.PickerSpec<gents.CommandName>?
  local actions
  require("gents.config").get().picker = function(spec)
    actions = spec
  end
  vim.cmd("Gents actions")
  local spec = assert(actions)
  local item = spec.items[#spec.items]
  eq(item.data, "rex-title")
  eq(lines("calls"), {})
  spec.actions[spec.default](item)
  wait_label("Planning")
  vim.api.nvim_exec_autocmds("VimLeavePre", { group = "gents_rex_pane_title" })
  wait_label("Editor")
end

T["wiping an owner hands off to an untitled session and takes a fresh snapshot later"] = function()
  setup(true)
  local first, second = H.new(), H.new()
  update(first, "Fix")
  wait_label("Fix")
  vim.api.nvim_buf_delete(first.buf, { force = true })
  wait_label("Editor")
  external("Build")
  update(second, "Review")
  wait_label("Review")
  update(second, second.cwd)
  wait_label("Build")
  eq(lines("writes"), { "Fix", "Editor", "Review", "Build" })
end

T["setup applies an existing title and preserves a manual rename at release"] = function()
  local owner = H.new()
  update(owner, "Existing")
  eq(lines("calls"), {})
  setup(true)
  wait_label("Existing")
  setup(true)
  external("Manual")
  setup(false)
  vim.api.nvim_exec_autocmds("VimLeavePre", { group = "gents_rex_pane_title" })
  wait_label("Manual")
  eq(lines("writes"), { "Existing" })
end

T["a failed launch never claims the pane and auto-resume keeps its turn"] = function()
  gents.setup({
    rex_pane_title = true,
    tools = {
      cat = { cmd = { "cat" } },
      flaky = {
        cmd = { "sh", "-c", 'if [ "$1" = --last ]; then read -r line; exit 1; fi; exec cat', "sh" },
        resume_last = { "--last" },
      },
    },
  })
  eq(pcall(gents.new, "flaky", { cmd = { dir .. "/missing" } }), false)
  eq(lines("calls"), {})
  local owner = assert(gents.new("flaky", { auto_resume = true }))
  local first_buf, second = owner.buf, H.new()
  update(owner, "Original")
  wait_label("Original")
  update(second, "Review")
  vim.fn.chansend(assert(owner.job), "fail now\n")
  H.wait(function()
    return owner.buf ~= first_buf
  end)
  update(owner, "Fresh")
  wait_label("Fresh")
  gents.close(owner.id)
  wait_label("Review")
  eq(lines("writes"), { "Original", "Fresh", "Review" })
end

T["the Rex label is safe argv and preserves the session's full title"] = function()
  setup(true)
  local owner = H.new()
  local prefix = "-$(foo); "
  local title = prefix .. string.rep("語", 150)
  update(owner, title)
  wait_label(prefix .. string.rep("語", 128 - #prefix))
  eq(owner.title, title)
  update(owner, "　A" .. vim.fn.nr2char(0x85) .. "B　")
  wait_label("A B")
  update(owner, "A　B")
  wait_label("A　B")
end

T["failed inspection or rename can recover on a subsequent title change"] = function()
  setup(true)
  local owner = H.new()
  vim.fn.writefile({}, dir .. "/fail")
  update(owner, "First")
  H.wait(function()
    return vim.fn.filereadable(dir .. "/failed") == 1
  end)
  eq(lines("writes"), {})
  vim.fn.delete(dir .. "/fail")
  vim.fn.writefile({}, dir .. "/reject")
  update(owner, "Second")
  H.wait(function()
    return vim.fn.filereadable(dir .. "/rejected") == 1
  end)
  wait_label("Editor")
  vim.fn.delete(dir .. "/reject")
  update(owner, "Third")
  wait_label("Third")
  gents.close(owner.id)
  wait_label("Editor")
end

T["a pending rename finishes before handoff and normal shutdown restoration"] = function()
  setup(true)
  local first, second = H.new(), H.new()
  vim.fn.writefile({}, dir .. "/delay")
  update(first, "First")
  update(second, "Second")
  H.wait(function()
    return #lines("writes") == 1
  end)
  gents.close(first.id)
  H.wait(function()
    return #lines("writes") == 2
  end)
  vim.api.nvim_exec_autocmds("VimLeavePre", { group = "gents_rex_pane_title" })
  eq(lines("writes"), { "First", "Second", "Editor" })
  wait_label("Editor")
end

T["restore after disabling"] = test.new_set({ parametrize = { { "inspect" }, { "rename" } } }, {
  ---@param command string
  ["recovers from one failed command without another session event"] = function(command)
    setup(true)
    local session = H.new()
    update(session, "Review")
    wait_label("Review")
    vim.fn.writefile({}, dir .. "/" .. command .. "-once")
    setup(false)
    wait_label("Editor")
    eq(vim.fn.filereadable(dir .. "/" .. command .. "-failed"), 1)
  end,
})

T["shutdown retries a failed restoration check only once"] = function()
  setup(true)
  update(H.new(), "Review")
  wait_label("Review")
  vim.fn.writefile({}, dir .. "/fail")
  vim.api.nvim_exec_autocmds("VimLeavePre", { group = "gents_rex_pane_title" })
  eq(lines("calls"), { "inspect", "rename", "inspect", "inspect" })
  vim.fn.delete(dir .. "/fail")
end

T["both inherited IDs and a Rex executable are required"] = function()
  local owner = H.new()
  update(owner, "Ready")
  vim.env.REX_SESSION = nil
  setup(true)
  eq(gents.rex_title(owner.id), nil)
  vim.env.REX_SESSION, vim.env.REX_BLOCK = "test-session", ""
  setup(true)
  eq(gents.rex_title(owner.id), nil)
  vim.env.REX_BLOCK, vim.env.PATH = "test-block", dir .. "/missing"
  setup(true)
  eq(gents.rex_title(owner.id), nil)
  vim.env.PATH = dir .. ":" .. assert(path)
  update(owner, "Renamed")
  eq(lines("calls"), {})
end

T["a nested Neovim leaves the enclosing Rex pane alone"] = function()
  vim.env.NVIM = dir .. "/parent.sock"
  setup(true)
  local session = H.new()
  update(session, "Nested conversation")
  eq(gents.rex_title(session.id), nil)
  gents.close(session.id)
  setup(false)
  eq(lines("calls"), {})
end

return T
