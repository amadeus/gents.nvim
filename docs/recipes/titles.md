# Conversation titles

Conversation titles help you find the right session when several CLIs are open.
When a CLI emits a terminal title, gents.nvim shows it in the session picker
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
:Gents focus claude #2
```

For a label you choose yourself, name the session when you create it:

```lua
require("gents").new("claude", { label = "review" })
```

You can then use `:Gents focus review` regardless of its displayed title.
Conversation titles are display text and are not command targets.

## Built-in title handling

Built-in parsers remove tool-specific wrappers so the picker can show the useful
part of a title. Custom tools use their cleaned terminal title automatically.

| Tool        | How gents.nvim handles its terminal title                                                                                                    |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude`    | Removes a leading activity marker (`✳`, `◐`, or `◑` followed by a space). `Claude Code` clears the title.                                    |
| `codex`     | Uses the thread-only title configured in [Codex setup](#codex-setup). The parser omits `Codex` and unnamed thread UUIDs.                     |
| `opencode`  | Keeps the text after `OC \| `. Other titles clear the conversation title.                                                                    |
| `omp`       | Removes `π: ` or `π ` followed by `>`, `!`, `:`, or any braille character (U+2800–U+28FF). Placeholders and unknown formats clear the title. |
| Other tools | Uses the cleaned terminal title without a dedicated parser.                                                                                  |

For example, Claude's `✳ Fix terminal navigation` becomes `Fix terminal
navigation`. OSC 0 and OSC 2 signals drive these updates; a tool that emits no
usable title continues to show its label and `Untitled`.

OMP's `π > Fix tests`, `π ⠋ Fix tests`, and `π: Fix tests` all become
`Fix tests`. Changes to its working spinner do not rename the buffer or emit
another title event. A directory-name fallback matching the gents.nvim session's
cwd basename is omitted. Resuming an OMP session recorded in another directory
can display that directory's basename as the conversation title. If an OMP
extension supplies a different terminal title format, use a custom parser below.
See the [OMP setup recipe](omp.md) for context sends and ready notifications.

## Codex setup

To show Codex conversation names, merge this setting into `~/.codex/config.toml`
(or `$CODEX_HOME/config.toml` if you use a custom config directory):

```toml
[tui]
terminal_title = ["thread"]
```

If you already have a `[tui]` section, add or update `terminal_title` there
instead of creating a second section. Start a new Codex session after saving.
No helper script or gents.nvim command override is needed: the built-in command
is simply `codex`. Keeping the setting in the config file avoids forcing Codex
into embedded mode with a command-line configuration override.

The parser expects the thread-only format and omits `Codex` and unnamed thread
UUIDs. It does not read Codex's config or inspect launch arguments. Codex's
default title includes activity and project information, so configure the
thread-only format above for conversation names. If you choose another format,
use a custom parser or disable title reporting below.

See the [Codex title settings](https://learn.chatgpt.com/docs/config-file/config-sample)
and [ready notification setup](ready.md#codex) for other settings in `[tui]`.

## Customize or disable titles

A custom parser lets you extract a conversation name from your CLI's title
format. This example turns `MyCLI: Fix terminal navigation` into `Fix terminal
navigation`:

```lua
require("gents").setup({
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
are omitted. See `:help gents.TitleParser` for the full contract.

Set `title = false` when you prefer stable labels in the picker and buffer names:

```lua
require("gents").setup({
  tools = {
    claude = { title = false },
    codex = { title = false },
  },
})
```

This changes title reporting for new sessions without changing the CLI's own
output. To also disable Codex title output, set an empty list in its config file:

```toml
[tui]
terminal_title = []
```

## Find sessions through native buffer tools

Readable buffer names help you recognize sessions in Neovim's own buffer tools.
A titled session is named `gents://2/claude · Fix terminal navigation`; without
a title, it uses a name such as `gents://2/claude #2`. The ID distinguishes
sessions that have the same title. Names follow title changes, with path
separators, control characters, and whitespace sanitized.

Use the gents.nvim session picker for normal navigation. Session buffers are
unlisted by default; `:ls!` includes them. If you want your usual buffer tools
to list new sessions, opt in with:

```lua
require("gents").setup({ buflisted = true })
```

This is an advanced escape hatch: buffer tools may still exclude terminals, and
deleting a session buffer stops its CLI. Use `:Gents hide` to keep it running.
See `:help gents-buffer-listing` for existing buffers and native navigation.

gents.nvim sessions cannot be restored by `:mksession`. We recommend
[excluding terminal buffers from saved sessions](../usage.md#session-restoration).

## Use titles in a statusline

You can show the current conversation in your statusline as well as the picker.
Session objects and `gents.status()` snapshots expose the full optional
`title`. See [statusline integration](statusline.md) for complete examples that
use the title when present and fall back to the session label.

`User GentsSessionTitle` fires when the normalized title changes. Its event
data contains `id` and optional `title`; an absent title means it was cleared.
Read `gents.status()` again when refreshing a cached statusline. See `:help
GentsSessionTitle` for the event contract.

## When a title is missing or stale

Titles reflect the signals the CLI sends. Generic signals may describe a
project, status, or screen rather than a conversation, and gents.nvim cannot
recover text the CLI omitted. Recognized reset titles clear the previous title;
empty signals may not reach the plugin, so a reset without a usable signal can
leave it stale. Exited sessions retain their last title and ignore later
updates.

The complete title behavior is documented in `:help gents-tool-titles` in the
[full help file](../../doc/gents.txt).
