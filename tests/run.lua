local ok, err = xpcall(function()
  assert(vim.v.errmsg == "", vim.v.errmsg)
  vim.opt.runtimepath:append(assert(vim.env.MINI_TEST_DIR, "MINI_TEST_DIR must point to mini.test"))

  local test = require("mini.test")
  test.setup({ collect = { emulate_busted = false } })

  local cases = test.collect()
  assert(#cases > 0, "No tests found in tests/test_*.lua")
  test.execute(cases, { reporter = test.gen_reporter.stdout({ quit_on_finish = true }) })
end, debug.traceback)

if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
