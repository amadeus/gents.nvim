local M = {}
local cwd = vim.fn.getcwd()

---@return nil
function M.reset()
  local gents = require("gents")
  for _, session in ipairs(gents.sessions()) do
    gents.close(session.id)
  end
  -- Live terminal buffers are deleted only after their PTY streams close.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      local job = vim.bo[buf].channel
      if job > 0 and vim.fn.jobwait({ job }, 0)[1] == -1 then
        vim.fn.jobstop(job)
        M.wait(function()
          return vim.fn.jobwait({ job }, 0)[1] ~= -1
        end)
      end
    end
  end
  vim.cmd.stopinsert()
  vim.cmd("silent tabonly!")
  vim.cmd("silent only!")
  vim.cmd("enew!")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and buf ~= vim.api.nvim_get_current_buf() then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  vim.cmd.cd(cwd)
  gents.setup({ tools = { cat = { cmd = { "cat" }, url = "https://example.com/cat" } } })
end

---@class gents.test.Session: gents.Session
---@field job integer

---@param opts? gents.NewOptions
---@return gents.test.Session
function M.new(opts)
  local session = assert(require("gents").new("cat", opts))
  assert(session.job and session.job > 0, "Expected a started terminal job")
  ---@cast session gents.test.Session
  return session
end

---@param predicate fun(): boolean
---@return nil
function M.wait(predicate)
  assert(vim.wait(2000, predicate, 10), "Timed out waiting for terminal job")
end

return M
