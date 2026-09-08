# Session information in your statusline

A statusline can identify the conversation in a session buffer and show how many
other sessions are running. agents.nvim supplies the data; you choose the text
and where it appears in your statusline.

## Name the current session

Use `agents.current()` in a statusline component to show the tool and its
conversation title, falling back to the stable session label. This example
returns an empty string for other buffers:

```lua
function _G.AgentsStatus()
  local session = require("agents").current()
  if not session then
    return ""
  end

  local name = session.title and (session.tool.name .. " · " .. session.title)
    or session.label
  return name .. (session.state == "exited" and " [exited]" or "")
end

vim.opt.statusline:append(" %{v:lua.AgentsStatus()}")
```

The final line appends the component to Neovim's native statusline. If you
use a statusline plugin, pass `AgentsStatus` where that plugin accepts a Lua
component function instead. For example, the component might show
`codex · Fix session focus` or `codex #2`.

Titles can change while a session is running. Read them when the statusline
renders instead of saving the initial value. See [conversation titles](titles.md)
for title handling and custom parsers.

## Count running and hidden sessions

To keep track of sessions while editing another buffer, use `agents.status()`.
It returns fresh snapshots of all sessions, including hidden and exited ones.
This component counts only running sessions and shows how many are hidden:

```lua
function _G.AgentsCount()
  local running, hidden = 0, 0
  for _, session in ipairs(require("agents").status()) do
    if session.state ~= "exited" then
      running = running + 1
      if not session.visible then
        hidden = hidden + 1
      end
    end
  end
  if running == 0 then
    return ""
  end
  return ("Agents %d (%d hidden)"):format(running, hidden)
end

vim.opt.statusline:append(" %{v:lua.AgentsCount()}")
```

`visible` means shown in the current tab. A session displayed only in another
tab counts as hidden. `state` describes startup or exit; it does not tell you
whether the agent is thinking, waiting for input, or finished with a task.

## Refresh when session information changes

If your statusline needs an explicit refresh when a title changes or a CLI
exits, request one from the corresponding User events:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = { "AgentsSessionTitle", "AgentsSessionExit" },
  callback = function()
    vim.schedule(function()
      vim.cmd("redrawstatus!")
    end)
  end,
})
```

Use your statusline plugin's refresh method if it caches component results. For
a count or visibility display, also refresh on normal buffer, window, and tab
changes: those can change what is visible without an agents.nvim command.

See `:help agents.current()`, `:help agents.status()`, and `:help agents-events`
in the [complete help reference](../../doc/agents.txt) for fields and events.
