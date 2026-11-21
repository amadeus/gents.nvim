local M = {}

local enabled = false
local busy = false
---@type string?, string?
local session_id, block_id
---@type string?, string?, string?, string?
local desired, original, applied, attempted

-- Rex trims Unicode whitespace when storing a label. Match its edge trimming
-- so a later ownership check compares exactly what the server stored.
local space = [=[[ \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]]=]
local edges = "^" .. space .. [[\+\|]] .. space .. [[\+$]]

---@return string?
local function owner_title()
  for _, session in ipairs(require("gents.session").list()) do
    if session.state ~= "exited" then
      if session.title then
        -- titles.update already cleans ASCII controls. Replace the C1 range too.
        local title = session.title:gsub("\194[\128-\159]", " ")
        title = vim.fn.substitute(title, edges, "", "g")
        title = vim.fn.strcharpart(title, 0, 128)
        title = vim.fn.substitute(title, edges, "", "g")
        return title ~= "" and title or nil
      end
      break
    end
  end
end

---@param args string[]
---@param done fun(result?: vim.SystemCompleted)
local function rex(args, done)
  local cmd = { "rex", "--autostart=false", "block" }
  vim.list_extend(cmd, args)
  local ok = pcall(vim.system, cmd, { text = true, timeout = 500 }, vim.schedule_wrap(done))
  if not ok then
    done()
  end
end

---@param result? vim.SystemCompleted
---@return string?
local function read_label(result)
  if result and result.code == 0 and result.signal == 0 and result.stdout then
    local ok, data = pcall(vim.json.decode, result.stdout)
    if ok and type(data) == "table" and type(data.block) == "table" then
      if type(data.block.label) == "string" then
        return data.block.label
      end
    end
  end
end

---@param retrying? boolean
local function sync(retrying)
  if not busy and not desired and not original then
    applied = nil
  end
  if busy or (desired == applied and not attempted) then
    return
  end
  -- Hold the target through release, even if setup disables the integration.
  if not original then
    session_id, block_id = vim.env.REX_SESSION, vim.env.REX_BLOCK
  end
  if not session_id or session_id == "" or not block_id or block_id == "" then
    return
  end
  local scope, block = session_id, block_id
  ---@param title? string
  ---@param success boolean
  local function finish(title, success)
    busy = false
    if desired ~= title then
      sync()
    elseif not success and not title and original and not retrying then
      -- After release there may be no more title events to trigger another attempt.
      busy = true
      vim.defer_fn(function()
        busy = false
        sync(true)
      end, 100)
    end
  end

  local requested = desired
  busy = true
  rex({ "inspect", "-s", scope, "--json", "--", block }, function(result)
    local current = read_label(result)
    if not current then
      finish(requested, false)
      return
    end
    -- An external rename becomes the baseline for any subsequent takeover.
    -- After a timeout, Rex may have applied either the previous or attempted label.
    if current ~= applied and current ~= attempted then
      original, applied = nil, nil
    end
    attempted = nil
    local title = desired
    local label = title or original
    if not label or label == current then
      busy = false
      applied = title
      if not title then
        original = nil
      end
      return
    end
    original = original or current
    attempted = label
    rex({ "rename", "-s", scope, "--", block, label }, function(write)
      local success = write ~= nil and write.code == 0 and write.signal == 0
      if success then
        applied, attempted = title, nil
        if not title then
          original = nil
        end
      end
      finish(title, success)
    end)
  end)
end

function M.refresh()
  desired = enabled and owner_title() or nil
  sync()
end

---@param on boolean
function M.setup(on)
  -- A nested Neovim inherits its parent's Rex pane IDs and gets $NVIM from :terminal.
  enabled = on
    and (vim.env.NVIM or "") == ""
    and (vim.env.REX_SESSION or "") ~= ""
    and (vim.env.REX_BLOCK or "") ~= ""
    and vim.fn.executable("rex") == 1
  local group = vim.api.nvim_create_augroup("gents_rex_pane_title", { clear = true })
  if enabled then
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = { "GentsSessionStart", "GentsSessionTitle", "GentsSessionExit" },
      callback = M.refresh,
    })
  end
  if enabled or busy or original then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        enabled = false
        M.refresh()
        -- Allow an in-flight rename, the ownership check, and restoration to finish.
        vim.wait(1600, function()
          return not busy
        end, 5)
      end,
    })
  end
  M.refresh()
end

return M
