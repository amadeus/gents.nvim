# Conversation titles

Tools that emit terminal titles add them to the session picker automatically,
for example `○  claude · Fix terminal navigation · /path/to/project`.
Titled sessions show the tool name and conversation title. Without a title,
the picker uses the session label with an `Untitled` placeholder, such as
`claude #2 · Untitled`. Displayed conversation titles are limited to 60 columns,
including `...` when shortened. Session data retains the complete title.

Commands and mappings target the session ID or label, such as `claude`,
`claude #2`, or your custom label. Titles appear in every picker adapter;
reopen the picker to see updated titles.

## Tool support

| Tool                    | Title source and behavior                                                                                                                           |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude`                | Terminal title with Claude's activity prefix removed. Manual names and generated topics can appear; a custom agent name can also be used by Claude. |
| `codex`                 | The built-in command requests the thread title with `-c 'tui.terminal_title=["thread"]'`. The unnamed thread UUID is omitted.                       |
| `opencode`, `opencode2` | Terminal title with `OC \| ` removed. OpenCode truncates long titles before sending them.                                                           |
| Other tools             | Cleaned terminal title emitted by the CLI.                                                                                                          |

OSC 0 and OSC 2 title updates work for built-in and custom tools. Without a
title signal, the session label and `Untitled` are shown. Dedicated parsers
refine the display for the tools listed above.

Claude and OpenCode keep their existing CLI settings; disabled terminal titles
produce no updates. Codex's option applies only to the launched process.
Its parser requires an explicit thread-only title setting in the final launch
arguments. A replacement command without that setting, a different title format,
or a later override of the whole `tui` table falls back to the session label
and `Untitled`. Keep the thread-only terminal title format enabled: changes to
that format through Codex's `/title` command cannot be detected. A custom
`title` callback can handle your own format.

Disable reporting with `title = false`. To also disable Codex's terminal title
output, replace its command:

```lua
require("agents").setup({
  tools = {
    claude = { title = false },
    codex = {
      cmd = { "codex", "-c", "tui.terminal_title=[]" },
      title = false,
    },
  },
})
```

A `cmd` override replaces the complete launch command. For a single session,
append a Codex override with `args`:

```lua
require("agents").new("codex", { args = { "-c", "tui.terminal_title=[]" } })
```

## Custom tools

Custom tools use their terminal titles automatically. To refine the text,
provide a parser that returns a string or `nil` to clear it. Returning `nil`
does not fall back to the raw title:

```lua
require("agents").setup({
  tools = {
    mycli = {
      cmd = { "mycli" },
      ---@param raw string
      ---@param _session agents.Session
      ---@return string?
      title = function(raw, _session)
        return raw:match("^MyCLI: (.+)$")
      end,
    },
  },
})
```

Control characters become spaces and surrounding whitespace is trimmed before
and after parsing. Empty titles and titles equal to the session's cwd or its
basename are omitted. The callback only receives nonempty OSC 0 or OSC 2 title
updates from that session's terminal.

Session objects and `agents.status()` snapshots expose optional `title` for
statuslines. Display the existing `label` when it is absent.
`User AgentsSessionTitle` fires only when the normalized title changes. Its
`ev.data` contains `id` and optional `title`; an absent title means it was
cleared. Read `agents.status()` again when refreshing a cached statusline.

## Limitations

Titles come from the CLI's terminal title signals. Recognized unnamed titles
clear the previous title; resets without a usable signal can leave it stale.
Empty title signals may not reach the plugin. Exit retains the last title and
subsequent updates are ignored.

Terminal titles are display text: generic titles may be project, status, or tool
names until a dedicated parser refines them. A custom Claude agent name or an
OpenCode plugin screen name can also appear instead of a conversation topic.
OpenCode can truncate titles before sending them; the plugin cannot recover
the missing text.

Authenticated live title updates remain unverified. References:
[Claude session naming](https://code.claude.com/docs/en/sessions#name-your-sessions),
[Codex title configuration](https://learn.chatgpt.com/docs/developer-commands?surface=cli#configure-terminal-title-items-with-title),
[OpenCode title implementation](https://github.com/anomalyco/opencode/blob/dev/packages/tui/src/app.tsx#L432-L459).
