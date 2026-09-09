# Sending context

Send the code, errors, or output you are working with to a CLI session without
copying it by hand. Run `:Gents send` from your source buffer, choose the context
you want to share, and gents.nvim pastes it into the destination session.

For a common request, skip the context picker and name a provider directly:

```vim
:Gents send buffer
```

This copies the whole buffer, including unsaved edits, and focuses the
destination so you can continue your message.

**NOTE:** it is generally recommended not to type out these commands manually,
but attach them to keymaps.

## Choose what to send

Providers let you share just the information the agent needs. Use a file reference
to point at code on disk, or copy text when the exact current content matters.

| Provider       | What it sends                                                                               |
| -------------- | ------------------------------------------------------------------------------------------- |
| `line`         | A file reference to the current line or selected line range.                                |
| `selection`    | Selected text as a code block, with common leading indentation removed.                     |
| `file`         | A reference to the current file.                                                            |
| `buffer`       | The whole buffer's current text as a code block, including unsaved edits.                   |
| `messages`     | Neovim's `:messages` history.                                                               |
| `diagnostics`  | Source buffer diagnostics, limited to those intersecting a captured selection when present. |
| `quickfix`     | All entries in the global quickfix list, in list order.                                     |
| `locationlist` | All entries in the source window's location list, in list order.                            |
| `terminal`     | The last 1,000 lines of an ordinary terminal, after trimming trailing blank lines.          |

The picker uses this order and omits unavailable entries. For example, `selection`
needs an active Visual or Select selection or an Ex range, and `locationlist`
needs a nonempty list. The quickfix and location lists are not filtered by the
source buffer or selection.

`line` and `file` need a buffer with a file path and send references rather than
unsaved content. Reference syntax follows the destination tool: the same line
can appear as `@src/main.lua:12` or, for Claude, `@src/main.lua#L12`. Paths use the
captured source working directory, even when the destination session has a
different directory. `selection` and `buffer` copy Neovim's current text.

To share a particular range without making a selection, use an Ex range:

```vim
:3,8Gents send
:3,8Gents send line
```

The first command copies lines 3 through 8; the second references those lines.
Lua mappings can capture characterwise, linewise, and blockwise selections when
they call `send()` while Visual or Select mode is still active. See
`:help gents-keymaps` for examples.

## Choose a session and keep working

Send from the buffer you want to discuss. The chosen text or file references
are sent to your CLI session.

With one existing session, send uses that session; with several, it opens the
session picker. If no session exists, choose a tool from the New Session
picker to start one and receive the context.

Name a destination when you already know which conversation needs the context,
or use `--no-focus` to stay in the editor:

```vim
:Gents send buffer --target claude #2
:Gents send diagnostics --no-focus
```

`--no-focus` still shows the destination if needed, then restores the invoking
window. A layout that replaces that window's buffer cannot restore its previous
buffer. In Lua, pass `{ focus = false }` as the second argument to `send()`.

For a request you want to submit immediately, pass `{ submit = true }` to Lua
`send()`. See `:help gents.send()` for submission and startup waiting behavior.

## Combine context with instructions

A single message can include several providers. For example, this sends a file
reference alongside its diagnostics:

```vim
:Gents send file diagnostics
```

Add your own instructions with a Lua composition:

```lua
require("gents").send({
  { text = "Explain this code:" },
  { any = { "selection", "line" } },
})
```

This asks about the selected text, falling back to a reference to the current
line when nothing is selected. `any` chooses the first available alternative.
Items are combined in order, and every outer item is required: if a requested
provider is unavailable, the whole send stops with a warning.

## Save requests you use often

Saved prompts give a composition a name so you can reuse its instructions with
the file or selection you are working on. Add them to your setup:

```lua
require("gents").setup({
  prompts = {
    explain = {
      { text = "Explain this code:" },
      { any = { "selection", "line" } },
    },
    review = { { text = "Review this code for bugs:" }, "buffer" },
  },
})
```

Run `:Gents send explain`, or choose `explain` from the context picker. Each use
reads the source context at that time. `:Gents send review diagnostics` combines
the review request with the current buffer's diagnostics.

Saved prompts appear first in the picker, sorted by name, when their required
context is available. In commands, a saved prompt takes precedence over a
provider with the same name. Strings passed to Lua `send()` or used inside a
prompt identify providers, not saved prompts. To reuse a composition in Lua,
keep its item list in a variable and pass that list to both setup and `send()`.

## Add your own context

Custom providers make project information or another plugin's output available
in the same picker and commands. For example, add a shorter terminal excerpt:

```lua
require("gents").provider("terminal_tail", {
  desc = "Last 50 terminal lines",
  render = function(ctx)
    return require("gents.providers").terminal(ctx, 50)
  end,
})
```

From an ordinary terminal, run `:Gents send terminal_tail`. The built-in
`terminal` provider keeps its 1,000-line limit. For a limit needed on just one
send, pass the function as an item instead:

```lua
require("gents").send({
  function(ctx)
    return require("gents.providers").terminal(ctx, 50)
  end,
})
```

A provider returns a list of text, path, or code parts, or `nil` when it does not
apply. Providers should read context without changing editor state: they run
while the picker builds its choices, even if you choose something else.

The complete provider, composition, and delivery contracts are in
`:help gents-context` in the [full help file](../../doc/gents.txt).
