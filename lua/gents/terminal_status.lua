local M = {}
local protocol = require("gents.status_protocol")
local initialized, reporting = false, false
---@type table<string, gents.ProgramState>
local states =
  { idle = "idle", working = "working", blocked = "blocked", done = "done", error = "error" }

---@class gents.ProgramEntry
---@field record gents.ProgramStatus
---@field updated integer Serial of the latest report, used for eviction.
---@field changed integer Serial of the latest report that changed the record.
---@field outer_id string

---@class gents.ProgramRecords
---@field session gents.Session
---@field records table<string, gents.ProgramEntry>
---@field serial integer
---@field count integer
---@field published table<string, string>

---@type table<integer, gents.ProgramRecords>
local sessions = {}

---@param body string
local function send(body)
  vim.api.nvim_ui_send("\027]7501;" .. body .. "\027\\")
end

---@param owner gents.ProgramRecords
---@param id string
---@return string?
local function inherited_app(owner, id)
  while true do
    local entry = owner.records[id]
    if entry and entry.record.app then
      return entry.record.app
    end
    if id == "" then
      return
    end
    id = id:match("^(.*)/[^/]+$") or ""
  end
end

---@param owner gents.ProgramRecords
local function publish(owner)
  if not reporting then
    return
  end
  ---@type table<string, boolean>
  local present = {}
  local ids = vim.tbl_keys(owner.records)
  table.sort(ids)
  for _, id in ipairs(ids) do
    local entry = owner.records[id]
    ---@type string?
    local title
    if id == "" and entry.record.title == nil then
      local label = owner.session.label:gsub("[%z\1-\31\127]", ""):gsub("\194[\128-\159]", "")
      if #label <= 192 and protocol.text_valid(label) then
        title = label
      end
    end
    local body = protocol.serialize(entry.outer_id, entry.record, inherited_app(owner, id), title)
    present[entry.outer_id] = true
    if owner.published[entry.outer_id] ~= body then
      send(body)
      owner.published[entry.outer_id] = body
    end
  end
  for id in pairs(owner.published) do
    if not present[id] then
      send("state=clear:id=" .. id)
      owner.published[id] = nil
    end
  end
end

---@param session gents.Session
---@param id string
---@param previous? gents.ProgramStatus
---@param current? gents.ProgramStatus
---@param reason gents.StatusReason
local function changed(session, id, previous, current, reason)
  local context = require("gents.events").context(session)
  ---@type gents.StatusChangedEvent
  local data = {
    id = context.id,
    tool = context.tool,
    label = context.label,
    title = context.title,
    buf = context.buf,
    win = context.win,
    visible = context.visible,
    focused = context.focused,
    record_id = id,
    previous = previous and vim.deepcopy(previous) or nil,
    current = current and vim.deepcopy(current) or nil,
    reason = reason,
  }
  require("gents.events").emit("GentsStatusChanged", data)
end

---@param owner gents.ProgramRecords
---@param predicate fun(id: string, record: gents.ProgramStatus): boolean
---@param reason gents.StatusReason
local function remove(owner, predicate, reason)
  ---@type table<string, gents.ProgramStatus>
  local removed = {}
  for id, entry in pairs(owner.records) do
    if predicate(id, entry.record) then
      removed[id] = entry.record
      owner.records[id] = nil
      owner.count = owner.count - 1
    end
  end
  publish(owner)
  local ids = vim.tbl_keys(removed)
  table.sort(ids)
  for _, id in ipairs(ids) do
    changed(owner.session, id, removed[id], nil, reason)
  end
end

---Remove every record once the agent goes away.
---@param session gents.Session
---@param reason "exit"|"close"|"buffer"|"shutdown"
function M.detach(session, reason)
  local owner = sessions[session.id]
  if not owner then
    return
  end
  sessions[session.id] = nil
  if next(owner.published) then
    send("state=clear:id=gents/" .. session.id)
    owner.published = {}
  end
  remove(owner, function()
    return true
  end, reason)
end

---Choose the one status a session picker row shows: any blocked record, the
---root's preferred over the most recently changed child; otherwise the root
---record's own state. Idle and missing root records show nothing.
---@param session gents.Session
---@return { state: gents.ProgramState, kind?: gents.ProgramKind }?
function M.display(session)
  local owner = sessions[session.id]
  if not owner then
    return
  end
  ---@type gents.ProgramEntry?
  local blocked
  for id, entry in pairs(owner.records) do
    if
      entry.record.state == "blocked"
      and (
        not blocked
        or id == ""
        or blocked ~= owner.records[""] and entry.changed > blocked.changed
      )
    then
      blocked = entry
    end
  end
  local entry = blocked or owner.records[""]
  if entry and entry.record.state ~= "idle" then
    return { state = entry.record.state, kind = entry.record.kind }
  end
end

---@param enabled boolean
function M.setup(enabled)
  if not initialized then
    initialized = true
    local group = vim.api.nvim_create_augroup("gents_terminal_status", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        local owners = vim.tbl_values(sessions)
        for _, owner in ipairs(owners) do
          M.detach(owner.session, "shutdown")
        end
      end,
    })
  end
  if enabled == reporting then
    return
  end
  if not enabled then
    for _, owner in pairs(sessions) do
      if next(owner.published) then
        send("state=clear:id=gents/" .. owner.session.id)
        owner.published = {}
      end
    end
  end
  reporting = enabled
  if enabled then
    for _, owner in pairs(sessions) do
      publish(owner)
    end
  end
end

---@param session gents.Session
---@param sequence string
---@param terminator? string
function M.receive(session, sequence, terminator)
  if require("gents.session").get(session.id) ~= session or session.state == "exited" then
    return
  end
  if sequence == "\027]7501;?" or sequence:match("^\027%]7501;%?;") then
    if session.job then
      vim.fn.chansend(session.job, "\027]7501;?\027\\")
    end
    return
  end
  local report = protocol.parse(sequence, terminator)
  if not report then
    return
  end
  local owner = sessions[session.id]
  if not owner then
    owner = { session = session, records = {}, serial = 0, count = 0, published = {} }
    sessions[session.id] = owner
  end
  local id, state = report.id, report.state
  if state == "clear" then
    remove(owner, function(candidate)
      return id == "" or candidate == id or candidate:sub(1, #id + 1) == id .. "/"
    end, "clear")
    return
  end
  local activity = states[state]
  local entry = owner.records[id]
  if not entry and owner.count >= 256 then
    local oldest, timestamp = "", math.huge
    for candidate, record in pairs(owner.records) do
      if record.updated < timestamp then
        oldest, timestamp = candidate, record.updated
      end
    end
    remove(owner, function(candidate)
      return candidate == oldest
    end, "evicted")
    if sessions[session.id] ~= owner then
      return
    end
  end
  ---@type gents.ProgramStatus
  local current = {
    state = activity,
    kind = report.kind,
    msg = report.msg,
    progress = report.progress,
    app = report.app,
    title = report.title,
  }
  local previous = entry and entry.record or nil
  local repeated = previous ~= nil and vim.deep_equal(previous, current)
  owner.serial = owner.serial + 1
  owner.records[id] = {
    record = current,
    updated = owner.serial,
    -- Repeats emit no change event, so they must not change what is displayed.
    changed = entry and repeated and entry.changed or owner.serial,
    -- Flat mapped leaves avoid clearing descendants when a parent is evicted.
    outer_id = entry and entry.outer_id or "gents/" .. session.id .. "/r" .. owner.serial,
  }
  if not entry then
    owner.count = owner.count + 1
  end
  publish(owner)
  if repeated then
    return
  end
  changed(session, id, previous, current, "report")
  local ready = current.state == "done" and (not previous or previous.state ~= "done")
    or current.state == "blocked" and (not previous or previous.state ~= "blocked" or previous.kind ~= current.kind or previous.msg ~= current.msg)
    or current.state == "idle" and previous ~= nil and previous.state ~= "idle"
  if
    ready
    and sessions[session.id] == owner
    and owner.records[id]
    and owner.records[id].record == current
  then
    local context = require("gents.events").context(session)
    ---@type gents.ReadyEvent
    local data = {
      id = context.id,
      tool = context.tool,
      label = context.label,
      title = context.title,
      buf = context.buf,
      win = context.win,
      visible = context.visible,
      focused = context.focused,
      record_id = id,
      current = vim.deepcopy(current),
    }
    require("gents.events").emit("GentsReady", data)
  end
end

return M
