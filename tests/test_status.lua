local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

T["status returns independent snapshots with live visibility"] = function()
  local session = H.new({ label = "review" })
  session.title = "Investigate flaky tests"
  local status = gents.status()
  eq(status, {
    {
      id = session.id,
      tool = "cat",
      label = "review",
      title = "Investigate flaky tests",
      cwd = session.cwd,
      visible = true,
      state = "starting",
    },
  })
  status[1].label = "changed"
  status[1].title = "changed"
  eq(session.label, "review")
  eq(session.title, "Investigate flaky tests")
  session.title = nil
  eq(gents.status()[1].title, nil)
  vim.cmd.enew()
  eq(gents.status()[1].visible, false)
  gents.show(session.id)
  eq(gents.status()[1].visible, true)
  gents.close(session.id)
  eq(gents.status(), {})
end

T["status visibility follows native tab navigation"] = function()
  local session = H.new()
  local status = gents.status()
  eq(status[1].visible, true)
  vim.cmd.tabnew()
  eq(gents.status()[1].visible, false)
  eq(status[1].visible, true)
  vim.cmd.vsplit()
  vim.api.nvim_win_set_buf(0, session.buf)
  eq(gents.status()[1].visible, true)
  vim.cmd.tabprevious()
  eq(gents.status()[1].visible, true)
  vim.cmd.enew()
  eq(gents.status()[1].visible, false)
  vim.cmd.tabnext()
  eq(gents.status()[1].visible, true)
  vim.cmd.tabprevious()
  eq(gents.status()[1].visible, false)
end

T["a statusline reflects hidden sessions, show, hide, and exit"] = function()
  _G.gents_test_status = function()
    ---@type string[]
    local labels = {}
    for _, status in ipairs(gents.status()) do
      labels[#labels + 1] = status.label
        .. ":"
        .. status.state
        .. ":"
        .. (status.visible and "visible" or "hidden")
    end
    return table.concat(labels, ",")
  end
  test.finally(function()
    _G.gents_test_status = nil
  end)
  local function render()
    return vim.api.nvim_eval_statusline("%!v:lua.gents_test_status()", {}).str
  end
  local session = H.new({ cmd = { "sh", "-c", "read signal; exit 7" } })
  eq(render(), "cat:starting:visible")
  gents.hide(session.id)
  eq(render(), "cat:starting:hidden")
  gents.show(session.id)
  eq(render(), "cat:starting:visible")
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return session.state == "exited"
  end)
  eq(render(), "cat:exited:visible")
end

return T
