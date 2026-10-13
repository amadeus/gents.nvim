# Native agent status and readiness

Agents that implement the [Program Status Protocol (OSC 7501)](https://www.superlogical.com/rex/docs/build/program-status)
can tell gents.nvim when they are working, waiting for input, finished, or have
failed. Gents receives each report from its session's terminal buffer and emits
User autocmds. Native protocol support is required for these features; check the
CLI version you use. This contract applies equally to Codex, Claude Code,
OpenCode, and custom tools.

## React when an agent finishes or needs input

`GentsReady` fires when a record first reports `done` or transitions to `done`,
for a new `blocked` request, or for a return to `idle` after an observed
non-idle state on the same record. Initial idle and identical reports do not
fire it. Metadata updates to a record that is already done do not fire it
again. Changing a blocked request's kind or message does; title/progress/app
updates alone do not. An `error` report is available through
`GentsStatusChanged`.

Notify when a session is hidden from the current tab:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "GentsReady",
  callback = function(ev)
    if not ev.data.visible then
      local name = ev.data.title or ev.data.label
      local status = ev.data.current
      local message = status.msg
        or (status.state == "done" and "Work finished" or "Waiting for input")
      vim.notify(name .. ": " .. message)
    end
  end,
})
```

The event includes `id`, `tool`, `label`, optional conversation `title`, `buf`,
optional current-tab `win`, `visible`, and `focused`. A session shown only in
another tab counts as hidden. `record_id` is the native record ID; `""` denotes
the terminal's root. `current` is the complete native snapshot, including its
own optional `title`, distinct from the conversation title.

## Observe every record change

`GentsStatusChanged` includes the same session metadata and `record_id`, plus
`previous`, `current`, and `reason`. An absent `previous` means creation; an
absent `current` means removal. Snapshots contain `state` and optional `kind`,
`msg`, `progress`, `app`, and `title`. Each report replaces the record, so omitted
fields disappear. `app` in the snapshot is the producer's explicit field;
Gents resolves inherited app names when relaying to the host.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "GentsStatusChanged",
  callback = function(ev)
    local data = ev.data
    if data.current then
      print(data.tool, data.record_id, data.current.state)
    else
      print(data.tool, data.record_id, "removed", data.reason)
    end
  end,
})
```

Reasons are `report`, `clear`, `prompt`, `exit`, `close`, `buffer`, `shutdown`,
and `evicted` (the record capacity was reached). Identical snapshots emit no
change event. Stored records are updated before callbacks run, and event
snapshots are copies. Events fire for focused and hidden sessions, independently
of outward reporting. Existing session lifecycle, title, and send events keep
their separate roles. Session `state = "ready"` governs startup input delivery;
it is unrelated to the agent's activity or `GentsReady`.

## Terminal status indicators

To send these records to a host terminal application that supports OSC 7501,
merge this option into your existing setup:

```lua
require("gents").setup({ terminal_status = true })
```

The default is `false`; local status events and capability replies still work.
Your event callbacks can use `vim.notify()` to display Neovim alerts independently
of host-terminal reporting, including in GUI clients.

Gents forwards separate records for every session and worker, preserving native
states and supplied fields. It scopes host IDs under `gents/<session-id>` using
bounded record IDs, resolves app inheritance, and uses the targeting label as a
root title fallback. The terminal application is responsible for choosing which
records to display and how to show them. GUI Neovim clients without a host terminal
cannot show terminal indicators through this relay.

Focus and navigation do not clear native records. Disabling reporting clears
Gents' host records and keeps local snapshots; enabling it republishes them.
Native `clear` removes its record and descendants only within its own session.
Records change only through the agent's own reports until the agent goes away:
job exit, session close, buffer removal, and Neovim shutdown clear the owned
records. A new shell prompt does not expire them. There is no heartbeat. The
Sessions picker shows the same records as status glyphs; see
`:help gents-picker-session-rows`.

Soft resets and alternate-screen switches preserve records. Neovim currently
does not expose full terminal resets (RIS) to `TermRequest`, so Gents cannot
clear native records in response to RIS. A producer can explicitly report
`state=clear`. This is a limitation of full protocol conformance.

See `:help GentsReady`, `:help GentsStatusChanged`, and `:help gents-program-status`
for the full contracts.
