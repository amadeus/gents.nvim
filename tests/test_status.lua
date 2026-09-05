local test = require("mini.test")
local H = require("tests.helpers")
local agents = require("agents")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

T["status returns independent snapshots with live visibility"] = function()
  local session = H.new({ label = "review" })
  local status = agents.status()
  eq(status, {
    {
      id = session.id,
      tool = "cat",
      label = "review",
      cwd = session.cwd,
      visible = true,
      state = "starting",
    },
  })
  status[1].label = "changed"
  eq(session.label, "review")
  vim.cmd.enew()
  eq(agents.status()[1].visible, false)
  agents.show(session.id)
  eq(agents.status()[1].visible, true)
  agents.close(session.id)
  eq(agents.status(), {})
end

T["a statusline reflects hidden sessions, show, hide, and exit"] = function()
  _G.agents_test_status = function()
    ---@type string[]
    local labels = {}
    for _, status in ipairs(agents.status()) do
      labels[#labels + 1] = status.label
        .. ":"
        .. status.state
        .. ":"
        .. (status.visible and "visible" or "hidden")
    end
    return table.concat(labels, ",")
  end
  test.finally(function()
    _G.agents_test_status = nil
  end)
  local function render()
    return vim.api.nvim_eval_statusline("%!v:lua.agents_test_status()", {}).str
  end
  local session = H.new({ cmd = { "sh", "-c", "read signal; exit 7" } })
  eq(render(), "cat:starting:visible")
  agents.hide(session.id)
  eq(render(), "cat:starting:hidden")
  agents.show(session.id)
  eq(render(), "cat:starting:visible")
  vim.fn.chansend(session.job, "go\n")
  H.wait(function()
    return session.state == "exited"
  end)
  eq(render(), "cat:exited:visible")
end

return T
