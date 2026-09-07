# Sending context

`:Agents send` offers providers that apply to the captured source buffer.
Each provider inserts a file reference or text into the agent's input:

| Provider    | What it sends                                                                                 |
| ----------- | --------------------------------------------------------------------------------------------- |
| `line`      | A file reference with the current line or selected line range, such as `@src/main.lua:12-15`. |
| `selection` | The selected text as a code block, with common leading indentation removed.                   |
| `file`      | A reference to the current file, such as `@src/main.lua`.                                     |
| `buffer`    | The entire buffer's current text as a code block, including unsaved edits.                    |

Reference syntax is formatted for the selected tool. `selection` and `buffer`
copy text directly from Neovim into the agent's input, including unsaved edits.

If no agent session exists, choosing context opens the New Session picker.
Select a tool to launch it and send the captured context once it is ready for
input. The new session starts in the source window's captured working directory.

You can also send providers directly, for example `:Agents send line` or
`:Agents send buffer`.

- In an ordinary terminal: `:Agents send terminal` sends the last 1,000 lines,
  after trimming trailing blank lines.
- Anywhere with message history: `:Agents send messages` sends `:messages`.

The built-in choices start with `line`, `selection`, `file`, `buffer`, and
`messages`, followed by the other providers. Unavailable entries are omitted,
so `selection` appears between `line` and `file` only when text is selected.
Sending from an agents session uses the previous non-session window as its source.

Register custom providers with `require("agents").provider(name, spec)`.
The spec supplies a `desc` and a `render(ctx)` function that returns a list
of text, file-reference, or code-block parts, or `nil` when it does not apply.

To choose a terminal scrollback limit for one send, use an inline provider:

```lua
local agents = require("agents")
local providers = require("agents.providers")

agents.send({
  function(ctx)
    return providers.terminal(ctx, 50)
  end,
})
```

`providers.terminal(ctx, limit)` reads `ctx.buf`, including when that buffer
belongs to an agents session. The limit must be a positive integer. The
registered provider keeps its 1,000-line default.
