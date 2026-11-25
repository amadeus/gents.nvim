local M = {}

local automatic = false
local watching = false
local busy = false
local recheck = false
---@type gents.Session?
local selected
---@type string?
local block_id
---@type string?, string?, string?, string?
local desired, original, applied, attempted

-- Rex trims Unicode whitespace when storing a label. Match its edge trimming
-- so a later ownership check compares exactly what the server stored.
local space = [=[[ \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]]=]
local edges = "^" .. space .. [[\+\|]] .. space .. [[\+$]]

---@param session gents.Session
---@return boolean
local function running(session)
  return session.state ~= "exited"
end

---@return gents.Session?
local function title_session()
  local sessions = require("gents.session")
  if selected and sessions.get(selected.id) == selected and running(selected) then
    return selected
  end
  selected = nil
  if not automatic then
    return
  end
  for _, session in ipairs(sessions.list()) do
    if running(session) then
      return session
    end
  end
end

---@return string?
local function owner_title()
  local session = title_session()
  if session and session.title then
    -- titles.update already cleans ASCII controls. Replace the C1 range too.
    local title = session.title:gsub("\194[\128-\159]", " ")
    title = vim.fn.substitute(title, edges, "", "g")
    title = vim.fn.strcharpart(title, 0, 128)
    title = vim.fn.substitute(title, edges, "", "g")
    return title ~= "" and title or nil
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
  if busy then
    return
  end
  if not desired then
    recheck = false
  end
  if not desired and not original then
    applied = nil
  end
  if desired == applied and not attempted and not recheck then
    return
  end
  -- Hold the target through release, even if setup disables the integration.
  if not original then
    block_id = vim.env.REX_BLOCK
  end
  if not block_id or block_id == "" then
    return
  end
  local block = block_id
  ---@param title? string
  ---@param success boolean
  local function finish(title, success)
    busy = false
    if desired ~= title or recheck then
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
  recheck = false
  busy = true
  rex({ "inspect", "--json", "--", block }, function(result)
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
      applied = title
      if not title then
        original = nil
      end
      finish(title, true)
      return
    end
    original = original or current
    attempted = label
    rex({ "rename", "--", block, label }, function(write)
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
  desired = (automatic or selected) and owner_title() or nil
  sync()
end

---@return boolean
function M.available()
  -- A nested Neovim inherits its parent's Rex block ID and gets $NVIM from :terminal.
  return (vim.env.NVIM or "") == ""
    and (vim.env.REX_BLOCK or "") ~= ""
    and vim.fn.executable("rex") == 1
end

local function watch()
  if watching then
    return
  end
  local group = vim.api.nvim_create_augroup("gents_rex_pane_title", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "GentsSessionStart", "GentsSessionTitle", "GentsSessionExit" },
    callback = M.refresh,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      automatic, selected = false, nil
      M.refresh()
      -- Allow an in-flight rename, the ownership check, and restoration to finish.
      vim.wait(1600, function()
        return not busy
      end, 5)
    end,
  })
  watching = true
end

---@param target? integer|string|false
---@return gents.Session?
function M.select(target)
  if not M.available() then
    return
  end
  ---@param session? gents.Session
  ---@return gents.Session?
  local function choose(session)
    -- A session can exit while the picker is open.
    if M.available() and (not session or running(session)) then
      selected = session
      if session then
        watch()
      end
      -- An explicit choice should see any label the user has set in Rex.
      recheck = true
      M.refresh()
      return session
    end
  end
  if target == false then
    return choose(nil)
  elseif target ~= nil then
    assert(
      type(target) == "number" or type(target) == "string",
      "gents: rex_title expects a session ID, a label, or false to reset"
    )
    return require("gents.target").with(target, choose, nil, running)
  end
  local candidates = vim.tbl_filter(running, require("gents.session").list())
  if #candidates == 1 then
    return choose(candidates[1])
  elseif #candidates > 1 then
    require("gents.picker").sessions(
      candidates,
      choose,
      nil,
      { select_prompt = "Gents: Rex pane title" }
    )
  end
end

---@param on boolean
function M.setup(on)
  if (automatic and not on) or (selected and not M.available()) then
    selected = nil
  end
  automatic = on and M.available()
  if automatic then
    watch()
  end
  M.refresh()
end

return M
