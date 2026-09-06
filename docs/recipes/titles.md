# Conversation titles

Tools that emit terminal titles add them to the session picker automatically,
for example `claude · Fix terminal navigation  [hidden]  /path/to/project`.

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
title signal, only the session label is shown. Dedicated parsers refine the
display for the tools listed above.

Claude and OpenCode keep their existing CLI settings; disabled terminal titles
produce no updates. Codex's option applies only to the launched process.
Its parser requires an explicit thread-only title setting in the final launch
arguments. A replacement command without that setting, a different title format,
or a later override of the whole `tui` table falls back to session labels.
Leave the thread-only format enabled: later `/title` changes inside Codex cannot
be detected. A custom `title` callback can handle your own format.

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

## Limits and verification

Titles come from the CLI's terminal title signals. Recognized unnamed titles
clear the previous title; resets without a usable signal can leave it stale.
Neovim 0.12.4 did not emit `TermRequest` for empty title sequences in
testing. Exit retains the last title and subsequent updates are ignored.

Terminal titles are display text: generic titles may be project, status, or tool
names until a dedicated parser refines them. A custom Claude agent name or an
OpenCode plugin screen name can also appear instead of a conversation topic.
OpenCode's title formatter shortens topics longer than 40 characters to the
first 37 plus an ellipsis (`...` in 1.18.23, `…` in the inspected beta). The
plugin cannot recover the missing text.

Checked on 2026-09-06 using synthetic signals and inspected CLI source: Claude
Code 2.1.263, Codex 0.153.4, OpenCode 1.18.23, and the installed OpenCode 2 beta.
Codex's configuration override precedence was also checked. Authenticated live
title updates remain unverified. References:
[Claude session naming](https://code.claude.com/docs/en/sessions#name-your-sessions),
[Codex title configuration](https://learn.chatgpt.com/docs/developer-commands?surface=cli#configure-terminal-title-items-with-title),
[OpenCode title implementation](https://github.com/anomalyco/opencode/blob/dev/packages/tui/src/app.tsx#L432-L459).
