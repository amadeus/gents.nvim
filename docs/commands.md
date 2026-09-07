# Commands

`:Agents` opens the session picker. Add a command and its arguments to skip
picker choices:

```vim
:Agents actions
:Agents actions hide
:Agents actions hide claude #2
:Agents actions new claude --resume
:Agents actions send file diagnostics --target claude #2
```

The `actions` prefix accepts each command below. For example,
`:Agents actions hide` and `:Agents hide` perform the same action.

The Actions picker shows a short description of each command. Send Context
shows provider descriptions and marks presets as `Saved prompt`. Names and
descriptions are separated by aligned dots; Snacks renders the descriptions
and separators in a muted color. New Session uses the same treatment for
`Not installed` tools.

| Command                                                     | Behavior                                                                                                               |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `:Agents new [tool] [args...]`                              | Choose a tool or start the named tool with extra arguments.                                                            |
| `:Agents pick [target]`                                     | Choose a session, or show an explicit target.                                                                          |
| `:Agents focus [target]`                                    | Focus a session. Without a target, invoking from an agent returns to the previous window and leaves the agent visible. |
| `:Agents toggle [target]`                                   | Hide the selected session's views in the current tab, or show it if it is not visible there.                           |
| `:Agents hide [target]`                                     | Hide all views of the selected session and keep it running.                                                            |
| `:Agents close [target]`                                    | Stop and remove the selected session.                                                                                  |
| `:Agents send [provider...] [--no-focus] [--target target]` | Choose context, or send the named providers or prompts.                                                                |

A target is a session ID or its complete label, including spaces. It is
separate from the conversation title displayed in pickers. For `send`, put
providers and `--no-focus` before `--target`: everything after that separator
is the target. `:Agents send --target claude #2` opens the context picker with
that destination already selected.

The `line` and `file` providers send file references. `selection` and `buffer`
copy the selected text or entire buffer into the agent's input, including
unsaved edits. See [sending context](recipes/context.md) for examples and other
providers.

Sending context focuses the selected agent in terminal input mode. Use
`--no-focus` or the Lua option `focus = false` to keep focus in your editor:

```vim
:Agents send selection --no-focus
:Agents actions send file --no-focus --target claude #2
```

```lua
require("agents").send()
require("agents").send({ "selection" })
require("agents").send({ "selection" }, { focus = false })
```

`focus = false` shows hidden sessions using your configured layout and returns
focus to the originating window. With `layout = "current"`, the agent replaces
that window's buffer.

Use the Lua option `submit = true` to submit the message after inserting context.

Session commands choose a target in this order:

1. The explicit ID or label.
2. The session in the current buffer.
3. The only session, counting hidden sessions and sessions in other tabs.
4. The session picker.

From an editor with several sessions, `toggle` asks which one to show or hide,
including when one is already visible. An unmatched explicit target reports an
error.

Untargeted `pick` always opens the session picker, even from an agent or when
only one session exists. With no sessions, `pick`, `focus`, and `toggle` open
the tool picker; `hide` and `close` do nothing. After choosing context, `send`
opens the tool picker, starts the selected CLI, and queues the context for it.
Named providers skip the context picker.

Session rows start with `●` for visible in the current tab and `○` for hidden.
Markers, tool names or labels, conversation titles, and directories align in
columns, with muted dots between the name, title, and directory in Snacks.
Titles longer than 60 display columns end with `...`; sessions without
a title show `Untitled`, muted in Snacks. Exited sessions also show `[exited]`.
Directories under your home directory use `~`.

To use ASCII markers:

```lua
require("agents").setup({
  icons = { visible = "v", hidden = "h" },
})
```

The markers apply to every picker adapter. Snacks uses `DiagnosticInfo` for
visible markers, `Comment` for hidden markers, and `SnacksPickerDir` for
session directories, following your colorscheme.

`layout` chooses how new session windows open; it defaults to
`"botright vsplit"`, a full-height vertical split on the right.
`float` supplies the settings used when the chosen layout is `"float"`.
Changing `float` alone keeps that default layout.
To use floating windows by default with any picker:

```lua
require("agents").setup({
  layout = "float",
  float = { width = 0.8, height = 0.8, border = "rounded" },
})
```

The `float` values above are the built-in defaults, so that table can be
omitted. Partial settings such as `float = { border = "single" }` retain the
default width and height. In a lazy.nvim spec, put these settings in `opts`.

Enter runs the picker's default action:

- In New Session, it starts the selected tool using your configured `layout`,
  or the per-call layout supplied to `agents.new(nil, opts)`.
- In the session picker opened by `:Agents pick` or `agents.show()`, it focuses
  an existing window, including one in another tab, or opens one using your
  configured layout if no view exists. An explicit per-call layout requests
  that placement instead, even if the session already has a window.

Session pickers opened by `hide`, `close`, or `send` select the target for
that operation. Changing the default layout does not move existing windows.

Snacks layout shortcuts choose placement for that selection: Ctrl-V for a
vertical split, Ctrl-X for a horizontal split, Ctrl-T for a new tab, Ctrl-F
for a float using your `float` settings, and Ctrl-Enter for the window that
opened the picker. These choices override the configured or per-call layout.
For existing sessions, they open the requested view even if another view
exists, preserving the buffer, job, and other views. Custom adapters receive
the same named layout actions.

The Lua API also accepts a layout for one call without changing your defaults:

```lua
local agents = require("agents")
agents.new("claude", { layout = "split" })
agents.show("claude", {
  layout = { width = 0.6, height = 0.5, border = "single" },
})
```

`layout = "float"` uses the configured `float` table. An inline table is a
separate float configuration and must include `width` and `height`; it does
not inherit settings from `float`.

Widths and heights in `(0, 1]` are fractions of the editor; larger values are
cells, resolved when the float opens. Floats are centered unless you specify
`row` and `col`. Hiding a session closes its views, including floats, while
keeping the CLI running; closing it stops the CLI and removes the session.

Snacks pickers widen as needed to fit their binding hints, accounting for
borders and side-by-side previews. Wider configured layouts are preserved;
on small screens, hints may still be clipped. Sizing updates when the editor
is resized.

To hide the binding hints and keep your configured sizing and shortcuts:

```lua
require("agents").setup({
  picker = "snacks",
  picker_help = false,
})
```

Custom `layout` callbacks take no arguments and return a window ID. The
plugin assigns the session buffer after the callback returns. For example:

```lua
layout = function()
  vim.cmd("botright vsplit")
  return vim.api.nvim_get_current_win()
end
```

For floating windows, a callback can use `nvim_open_win(0, true, opts)`.
Use `TermOpen` or `FileType` hooks for buffer-specific settings.

Ranges work with `send`, including its composed form:

```vim
:2,5Agents send
:2,5Agents send line
:2,5Agents actions send --target claude #2
:2,5Agents actions
```

With a range and no providers, `send` copies the text in that range using
`selection`. Specify `line` to send a file reference to the range. The actions
menu retains the range for `send`; other actions reject ranges. A visual-mode
mapping calling `require("agents").actions()` preserves the selection as
context; choosing send opens the context picker, and other actions remain
available.

Completion follows each choice through `actions`, including tools, session
IDs and labels, providers, prompts, `--no-focus`, and `--target`. Labels with
spaces can be completed after partially typing them. Extra launch arguments
are not completed by the plugin.

Command arguments are separated by whitespace. Quotes and shell expressions
are treated as literal text. Use the Lua API for an argument containing spaces:

```lua
require("agents").new("claude", { args = { "--name", "Review this feature" } })
```
