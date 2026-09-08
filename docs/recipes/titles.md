# Conversation titles

Conversation titles help you find the right session when several CLIs are open.
When a CLI emits a terminal title, agents.nvim shows it in the session picker
and native buffer name. For example:

```text
○  claude · Fix terminal navigation · /path/to/project
```

Without a title, the picker shows the stable session label and `Untitled`, such
as `claude #2 · Untitled`. Titles appear in every picker adapter; reopen the
picker to see updates. Picker titles are limited to 60 display columns,
including `...` when shortened, while session data retains the complete title.

## Keep commands stable while titles change

Use the session's ID or label in commands and mappings. A conversation title can
change as the work develops without breaking a command such as:

```vim
:Agents focus claude #2
```

For a label you choose yourself, name the session when you create it:

```lua
require("agents").new("claude", { label = "review" })
```

You can then use `:Agents focus review` regardless of its displayed title.
Conversation titles are display text and are not command targets.

## Built-in title handling

Built-in parsers remove tool-specific wrappers so the picker can show the useful
part of a title. Custom tools use their cleaned terminal title automatically.

| Tool                    | How agents.nvim handles its terminal title                                                                        |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `claude`                | Removes a leading activity marker (`✳`, `◐`, or `◑` followed by a space). `Claude Code` clears the title.         |
| `codex`                 | The built-in command requests `tui.terminal_title=["thread"]`. The parser omits `Codex` and unnamed thread UUIDs. |
| `opencode`, `opencode2` | Keeps the text after `OC \| `. Other titles clear the conversation title.                                         |
| Other tools             | Uses the cleaned terminal title without a dedicated parser.                                                       |

For example, Claude's `✳ Fix terminal navigation` becomes `Fix terminal
navigation`. OSC 0 and OSC 2 signals drive these updates; a tool that emits no
usable title continues to show its label and `Untitled`.

Codex's parser uses titles only when the final launch arguments explicitly
request the thread-only format. A replacement `cmd` without that setting, a
different format, or a later override of the whole `tui` table prevents title
reporting. Changes to the format inside the running CLI cannot be detected from
its launch arguments. Use a custom parser if you choose another format.

## Customize or disable titles

A custom parser lets you extract a conversation name from your CLI's title
format. This example turns `MyCLI: Fix terminal navigation` into `Fix terminal
navigation`:

```lua
require("agents").setup({
  tools = {
    mycli = {
      cmd = { "mycli" },
      title = function(raw)
        return raw:match("^MyCLI: (.+)$")
      end,
    },
  },
})
```

The callback receives the cleaned title and session object, and returns a string
or `nil`. Returning `nil` clears the title rather than falling back to the raw
text. Control characters become spaces, surrounding whitespace is trimmed, and
empty titles or titles equal to the session's working directory or its basename
are omitted. See `:help agents.TitleParser` for the full contract.

Set `title = false` when you prefer stable labels in the picker and buffer names:

```lua
require("agents").setup({
  tools = {
    claude = { title = false },
    codex = { title = false },
  },
})
```

This changes title reporting for new sessions without changing the CLI's own
output. To also stop requesting Codex title output, replace its launch command:

```lua
require("agents").setup({
  tools = {
    codex = {
      cmd = { "codex", "-c", "tui.terminal_title=[]" },
      title = false,
    },
  },
})
```

A `cmd` override replaces the whole command. To append an override for just one
session:

```lua
require("agents").new("codex", { args = { "-c", "tui.terminal_title=[]" } })
```

## Find sessions through native buffer tools

Readable buffer names help you recognize sessions in Neovim's own buffer tools.
A titled session is named `agents://2/claude · Fix terminal navigation`; without
a title, it uses a name such as `agents://2/claude #2`. The ID distinguishes
sessions that have the same title. Names follow title changes, with path
separators, control characters, and whitespace sanitized.

Use the agents.nvim session picker for normal navigation. Session buffers are
unlisted by default; `:ls!` includes them. If you want your usual buffer tools
to list new sessions, opt in with:

```lua
require("agents").setup({ buflisted = true })
```

This is an advanced escape hatch: buffer tools may still exclude terminals, and
deleting a session buffer stops its CLI. Use `:Agents hide` to keep it running.
See `:help agents-buffer-listing` for existing buffers and native navigation.

agents.nvim sessions cannot be restored by `:mksession`. We recommend
[excluding terminal buffers from saved sessions](../usage.md#session-restoration).

## Use titles in a statusline

You can show the current conversation in your statusline as well as the picker.
Session objects and `agents.status()` snapshots expose the full optional
`title`. See [statusline integration](statusline.md) for complete examples that
use the title when present and fall back to the session label.

`User AgentsSessionTitle` fires when the normalized title changes. Its event
data contains `id` and optional `title`; an absent title means it was cleared.
Read `agents.status()` again when refreshing a cached statusline. See `:help
AgentsSessionTitle` for the event contract.

## When a title is missing or stale

Titles reflect the signals the CLI sends. Generic signals may describe a
project, status, or screen rather than a conversation, and agents.nvim cannot
recover text the CLI omitted. Recognized reset titles clear the previous title;
empty signals may not reach the plugin, so a reset without a usable signal can
leave it stale. Exited sessions retain their last title and ignore later
updates.

The complete title behavior is documented in `:help agents-tool-titles` in the
[full help file](../../doc/agents.txt).
