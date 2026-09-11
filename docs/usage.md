# Using gents.nvim

CLI sessions live in Neovim terminal buffers, so you can navigate and arrange
them alongside your other buffers. Set up a few keymaps to start sessions, move
between your code and a CLI, and send context from the buffer you are working
on.

A session has one CLI process and one terminal buffer. Windows are views of that
buffer: hiding a session keeps its process running, and showing it again returns
to the same conversation. The same session buffer can appear in multiple
windows, all connected to the same CLI process, much like any normal Neovim
buffer.

## Start with the defaults

After [installing the plugin](../README.md#installation), you can use the
built-in behavior with just a few keymaps:

- New sessions open in a full-height vertical split on the right.
- Pickers use `vim.ui.select` by default. We recommend the built-in Snacks
  adapter for its extra shortcuts and hints; adapters for mini.pick, Telescope,
  and fzf-lua offer the same actions.
- Sending context focuses the session so you can continue your message.
- Session buffers stay out of ordinary buffer lists. Use the session picker
  to find and manage them.

We recommend [snacks.nvim](https://github.com/folke/snacks.nvim) picker because
we've spent some time integrating additional functionality into it. It shows the
available actions and their shortcuts, so you can discover how to place, hide,
and close sessions as you use it. Install it alongside gents.nvim and enable it
with `picker = "snacks"`, as shown below.

Gents.nvim installs no keymaps by default. These four cover the everyday
flows; choose different keys if they fit your configuration better:

```lua
require("gents").setup({
  -- Use our custom snack picker which shows additional picker based mappings
  -- for extended functionality, just make sure you've also installed
  -- https://github.com/folke/snacks.nvim
  picker = "snacks",
  keys = {
    -- Pick a CLI tool and start a session.
    { "<leader>an", "new", mode = { "n", "t" } },
    -- Open a menu to manage sessions or send context.
    { "<leader>ac", "actions", mode = { "n", "t" } },
    -- Show or hide a session while keeping its CLI running.
    { "<leader>aa", "toggle", mode = { "n", "t" } },
    -- Send context from your file or Visual selection.
    { "<leader>as", "send", mode = { "n", "x" } },
  },
})
```

Each named action calls the matching Lua function: `new` calls
`require("gents").new()`, for example. Here, new, actions, and toggle work
in Normal mode and while typing in a session terminal. Send works in Normal
and Visual modes, from the buffer whose context you want to share.

Add these options to your existing setup instead of calling `setup()` twice.
With lazy.nvim, they go in `opts`.

## Work with sessions

The following walk-through uses the keys above. Start from a file in the
project you want to discuss.

### Start a conversation

Press `<leader>an` (**a**gents **n**ew is the mnemonic) and choose an installed CLI
tool. Its terminal opens on the right, ready for you to type. Use the CLI as you
normally would; it owns the conversation and how you interact with the agent.

Use new again when you want another session, including another instance of
the same tool. Each session has its own process and buffer.

### Move between the CLI and your code

Press `<leader>aa` to toggle hiding or showing your agent. You can also leave
the terminal visible and navigate between windows as usual. Hidden sessions
continue to run in the background, they are not paused.

With several sessions, toggle acts on the one you are in, or opens a session
picker when called from another buffer.

If you opened a session in a float, toggle brings it back in a float when no
view remains, using your current `float` settings. Opening that session in a
split through gents.nvim makes future toggles use the default layout again.
Each session remembers its most recent gents.nvim placement independently;
custom float dimensions and split arrangements are not remembered. Existing
views are still reused, including views in another tab.

Pass `layout` to control placement when showing a session:

```lua
require("gents").toggle(nil, { layout = false }) -- Use the configured default.
require("gents").toggle(nil, { layout = "float" }) -- Use your float defaults.
require("gents").toggle(nil, { layout = { width = 80, height = 0.8 } })
```

Pass a session ID or label instead of `nil` to target a specific session.
Omitting `layout` uses memory. `false` still reuses existing views; an explicit
layout chooses placement while preserving views elsewhere, just like `show`.
If the session is visible in the current tab, toggle hides it regardless of
`layout`. With no sessions, the New Session picker carries the explicit layout
into the launch. A newly opened view becomes the session's most recent placement.

### Bring context into the conversation

From a file, press `<leader>as` (**a**gents **s**end or **s**hare is the
mnemonic) to choose what to send. Select `line` or `file` to send a reference to
the session or make a Visual selection first and choose `selection` to copy that
text. There are a variety of other types of content providers that you can use
and you can also create your own.

With several sessions, you choose the destination after selecting context. If
none exists, the tool picker lets you start a new session for that request. You
can begin a conversation this way without opening a session first.

### Reach the other session actions

Press `<leader>ac` (**a**gents **c**ommands or a**c**tions is the mnemonic) to
open the Actions picker. Use `pick` to switch sessions, `focus` to change
windows while leaving a session visible, or `close` when you are done with a
session. Close stops its CLI and deletes its buffer; use toggle or hide when you
want it to keep running.

The menu adapts to your current buffer and whether sessions are running.
With none running, it offers new and send. As you find actions you use often,
give them their own keymaps.

The sections below cover window placement, pickers, and custom bindings.
For every option, command, and API contract, see `:help gents.nvim` or the
[complete help reference](../doc/gents.txt).

## Choose where sessions open

The default layout, `"botright vsplit"`, opens sessions in a full-height
vertical split on the right. Change `layout` to choose another default,
or pass a layout to a Lua call to place just that session view.

To open new session windows as floats:

```lua
require("gents").setup({
  layout = "float",
  -- Optional: change the default 80% width and height.
  float = { width = 60, height = 0.8, border = "rounded" },
})
```

`float` supplies the settings used by `layout = "float"` and the picker float
shortcut. Setting `float` alone does not change the default split layout.
Partial settings retain the other float defaults. In a lazy.nvim spec, put these
settings in `opts`.

Floats update their size and position when Neovim resizes. Use functions for
`width`, `height`, `row`, or `col` when you want a custom calculation. For
example, keep a 60-column float near the top-right corner:

```lua
require("gents").setup({
  layout = "float",
  float = {
    width = 60,
    height = function()
      return vim.o.lines - 4
    end,
    row = 0,
    col = function()
      return vim.o.columns - 1
    end,
    anchor = "NE",
    border = "rounded",
  },
})
```

These functions take no arguments and return numbers. They run when the view
opens and on `VimResized`. Existing windows resize in place, preserving focus,
input mode, and the running CLI. Each view keeps its original geometry
settings; later setup changes apply to newly opened views. Resizing reapplies
those settings, replacing manual size and position changes made with
`nvim_win_set_config()`. This applies to `layout = "float"` and inline float
tables. If you use a layout function, it manages its own window geometry.

When you press Enter in a picker:

- **New Session** starts the selected tool using your configured layout.
- **Sessions** switches to a window displaying the selected session, even
  if that window is in another tab. If no window displays the session, it
  opens using your configured layout.

To choose where a session opens for a single action, pass `layout` to the
Lua function. This uses the requested placement even if the session is
already displayed elsewhere:

```lua
local gents = require("gents")
gents.new("claude", { layout = "split" })
gents.show("claude", { layout = "current" })
gents.show("claude", {
  layout = { width = 0.6, height = 0.5, border = "single" },
})
```

`"current"` replaces the current window's buffer. An inline table opens a
float with those settings; it must include `width` and `height` and does
not inherit your configured `float` settings. Values in `(0, 1]` are
fractions of the editor; larger values are cells. This also applies to width
and height returned by functions. Dimensions round down to whole cells.
Floats are centered unless you supply `row` and `col`. Numeric proportions
and default centering follow editor resizes without callbacks. Dimensions stay
at least one cell when the editor is small; Neovim handles oversized dimensions
and off-screen placement.

Placing another view keeps the same buffer and CLI process. Hide and close
work with floats as well as splits. Changing your default layout does not
move existing windows. Session pickers opened by `hide`, `close`, or `send`
choose the target for that operation.

If you need your own window placement logic, a layout callback can create or
choose a window and return its ID. gents.nvim puts the session buffer there:

```lua
require("gents").setup({
  layout = function()
    vim.cmd("botright vsplit")
    return vim.api.nvim_get_current_win()
  end,
})
```

See `:help gents-layouts` for placement rules and float options.

## Pickers and shortcuts

gents.nvim opens its menus through `vim.ui.select` unless you choose a picker
adapter. With an adapter, the New Session and Sessions menus gain shortcuts to
place a session in a split, tab, or float, to open it in the current window, to
edit the launch command, and to hide or close a session. The adapters share
these actions; the keys follow each picker's conventions.

| `picker`      | Plugin                                                                                                                                                   | Native help           |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| `"snacks"`    | [folke/snacks.nvim](https://github.com/folke/snacks.nvim)                                                                                                | `?` and a hint footer |
| `"mini"`      | [nvim-mini/mini.pick](https://github.com/nvim-mini/mini.pick)                                                                                            | Shift-Tab info view   |
| `"telescope"` | [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) with [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | Ctrl-/ or `?`         |
| `"fzf-lua"`   | [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua) with the fzf executable                                                                          | F1                    |

We recommend Snacks because its picker also shows the shortcuts while you
choose, so you can discover the actions as you go:

```lua
require("gents").setup({
  picker = "snacks",
})
```

New Session and the session picker then offer:

| Key        | Placement                                               |
| ---------- | ------------------------------------------------------- |
| Ctrl-V     | Vertical split                                          |
| Ctrl-X     | Horizontal split                                        |
| Ctrl-T     | New tab                                                 |
| Ctrl-F     | Float using your `float` settings                       |
| Ctrl-Enter | Replace the buffer in the window that opened the picker |

These shortcuts choose placement for that selection, overriding the default
or per-call layout. For an existing session, they add the requested view
even if another view exists. When choosing a send target, they also send the
captured context and honor `submit`. With `focus = false`, you stay in the
sending window when the session opens elsewhere. The `current` placement
replaces that window's buffer and enters terminal input. The picker also shows
hints for other available actions, including hide and close. It widens to fit
those hints where screen space permits and updates sizing when Neovim is resized.

To hide the hints while keeping the shortcuts:

```lua
require("gents").setup({
  picker = "snacks",
  picker_help = false,
})
```

The other adapters bind the same actions to keys that fit their picker and list
them in that picker's own help, leaving any key your picker configuration
already uses untouched. See [use your preferred picker](recipes/pickers.md) for
their setup and key tables, `:help gents-picker-adapters` for the complete
comparison, and `:help gents-picker-highlights` for row highlight
customization.

Without a configured picker, gents.nvim uses `vim.ui.select`, including any
replacement you have configured. To build your own adapter, see the [custom
adapter notes](recipes/pickers.md#custom-adapters).

## Customize your keymaps

The named actions in `setup().keys` call Lua functions without arguments.
Use callbacks when you want to choose a particular tool, window layout, or
message. For example, add a key to start sessions in a float and another to
ask about the selected code:

```lua
vim.keymap.set("n", "<leader>af", function()
  require("gents").new(nil, { layout = "float" })
end, { desc = "Start a session in a float" })

vim.keymap.set({ "n", "x" }, "<leader>ae", function()
  require("gents").send({
    { text = "Explain this code:" },
    { any = { "selection", "line" } },
  })
end, { desc = "Ask about this code" })
```

The second mapping copies a selection, or sends a reference to the current
line when nothing is selected. See [sending context](recipes/context.md) for
other combinations and saved prompts.

You can also put a callback in `setup().keys` in place of a named action.
That helper keeps Terminal-mode mappings local to session buffers. With
`vim.keymap.set`, you choose the buffer scope yourself.

For `setup().keys`, omitting `mode` uses Normal, Visual, and Terminal modes.
Insert, Select, and combined Visual/Select modes are also supported. See
`:help gents-keymaps` for callbacks, options, and action names.

Lua calls that immediately resolve a session return it where documented.
Calls that open a picker return `nil`; the selection happens later through
callbacks. Do not chain another operation onto an assumed picker result.
See `:help gents-api` for each function's return value and
[statusline integration](recipes/statusline.md) for reading session state.

## Call commands directly

The actions used by your keymaps also have Ex commands. Use them from the
command line, or in a mapping when you want a fixed action:

```lua
vim.keymap.set("n", "<leader>aa", "<cmd>Gents toggle<cr>", {
  desc = "Show or hide a session",
})
```

| Command                                                    | What it does                                                                                                               |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `:Gents new [tool] [args...]`                              | Pick a CLI tool, or start the named tool with optional extra arguments.                                                    |
| `:Gents` or `:Gents pick [target]`                         | Choose an existing session, or show an explicit target. With no sessions, pick a tool to start.                            |
| `:Gents focus [target]`                                    | Focus a session. When called from a session without a target, return to the previous window and leave the session visible. |
| `:Gents toggle [target]`                                   | Hide the selected session's views in the current tab, or show it if it is not visible there.                               |
| `:Gents hide [target]`                                     | Hide the selected visible session's views in the current tab and keep its CLI running.                                     |
| `:Gents close [target]`                                    | Stop the selected CLI and delete its buffer.                                                                               |
| `:Gents send [provider...] [--no-focus] [--target target]` | Choose context, or send the named providers or saved prompts.                                                              |

The `actions` prefix also accepts a command and its arguments. These pairs
perform the same action:

```vim
:Gents hide
:Gents actions hide

:Gents new claude
:Gents actions new claude
```

See `:help gents-commands` for command syntax and completion.

## Choose a session

Commands usually infer which session you mean. From a session buffer, `hide`
hides that session in the current tab. From another buffer, it acts on the
only visible session or asks you to choose among visible sessions. Visibility
means a window in the current tab.

Target selection follows this order:

1. An explicit session ID or exact label.
2. The session in the current buffer.
3. The only session.
4. The session picker.

Hidden sessions, sessions in other tabs, and retained exited sessions count
when choosing a target, except that `hide` considers only visible sessions.
An existing nonvisible target is a no-op for `hide`; views in other tabs stay
open. An explicit target that does not exist reports an error. Labels such as
`claude #2` are stable targets; conversation titles are display text and cannot
be used as targets.

```vim
:Gents hide claude #2
:Gents focus 3
```

```lua
require("gents").show("claude #2")
require("gents").hide(3)
```

To hide all session views from the current tab, run `:Gents hide --all` or
`require("gents").hide(nil, { all = true })`. This skips selection and keeps
every CLI running. Do not combine `all` with a target. With no visible
sessions, hide does nothing.

There are a few differences between commands:

- `pick` without a target always opens a picker, even if only one session exists.
- `focus` without a target, called from a session, returns to the previous
  window and leaves terminal input mode. That window can contain any buffer.
- With no sessions, `pick`, `focus`, and `toggle` open the tool picker;
  `hide` and `close` do nothing.
- `send` opens the tool picker if it needs a new session, after you choose
  the context to send.

Lua calls also accept a predicate to narrow the candidates. See
`:help gents.Target` for examples.

## Send context directly

Send file references, selected code, or diagnostic messages from the buffer
you want to discuss. `line` and `file` send references; `selection` and
`buffer` copy text, including unsaved edits. Calling send from a gents.nvim
session buffer shows a warning and sends nothing.

```vim
:Gents send
:Gents send file diagnostics
:Gents send selection --no-focus --target claude #2
```

The first command opens the context picker. The others choose context
directly. For `send`, place providers and `--no-focus` before `--target`:
everything after that separator is the target's ID or label.

Sending focuses the destination in terminal input mode. Use `--no-focus`, or
`focus = false` in Lua, to return focus to the originating window after
showing the destination. With `layout = "current"`, that window displays
the session buffer.

```lua
require("gents").send({ "selection" }, { focus = false })
```

Ranges let you choose between copying lines and sending a reference to them:

```vim
:2,5Gents send
:2,5Gents send line
```

The first copies lines 2–5 using `selection`; the second sends a file
reference to that range. Ranges also work through `actions send`. Calling
`:2,5Gents actions` retains the range for send; other actions reject ranges.

See [sending context](recipes/context.md) for all providers, saved prompts,
custom providers, and optional message submission.

## Configure CLI tools

Use `tools` to change how a CLI starts, add a tool, or remove one you do not
use. A tool's `cmd` is an argument list, so it can also point to a wrapper
script. For example, if you have a CLI named `mycli` with a `chat` command:

```lua
require("gents").setup({
  tools = {
    mycli = { cmd = { "mycli", "chat" } },
    qwen = false,
  },
})
```

An override for a built-in tool keeps fields you do not specify. `cmd`
replaces its full command, and `env` replaces its configured environment
override table. Environment values are strings; `false` removes an inherited
variable from the CLI process. A tool's `enabled = false` hides it from the
picker while still allowing an explicit launch; `tools.name = false` removes
it altogether.

For one launch, use `args` to append arguments or `cmd` to replace the
command. Ex commands split on whitespace and treat quotes and shell
expressions literally. Lua preserves spaces within individual arguments:

```lua
require("gents").new("claude", { args = { "Explain this project" } })
```

Tool configuration changes affect newly created sessions. Each `setup()` call
starts from defaults, so collect your options in one call. See
`:help gents-tools` for built-in tools and environment examples, and
`:help gents-config` for configuration merging and timing.

For Oh My Pi (`:Gents new omp`), see the [OMP recipe](recipes/omp.md) for
large context pastes, conversation titles, and ready notifications.

## When a CLI exits

A CLI can exit on its own, for example after you use its quit command.
By default, `on_exit = "keep"` leaves the terminal buffer and its output
available to read. The session picker marks it `[exited]`; showing it does
not restart the CLI.

To remove the buffer automatically when the process exits successfully:

```lua
require("gents").setup({
  on_exit = "close",
})
```

An unsuccessful exit still keeps the output so you can read the error.
`:Gents close` always stops the CLI and deletes its buffer, regardless of
`on_exit`. Use `hide` to keep a session running. See `:help gents-on-exit`.

## Ordinary buffer pickers

Use `:Gents pick` to browse sessions and choose their placement. If you need
session buffers in ordinary buffer lists instead, `buflisted = true` is an
advanced escape hatch:

```lua
require("gents").setup({
  buflisted = true,
})
```

This applies to new session buffers. They participate in `:ls`, buffer
cycling, and buffer cleanup; bulk deletion can stop their CLIs. Pickers
that filter out terminals may still omit them. Selecting a hidden session's
buffer continues the same live session, using that picker's window placement.
See [conversation titles](recipes/titles.md) for buffer names.

## Session restoration

gents.nvim sessions cannot be restored by `:mksession`. If you use it, we
recommend excluding terminal buffers from saved sessions:

```lua
vim.opt.sessionoptions:remove("terminal")
```
