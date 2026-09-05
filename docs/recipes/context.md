# Sending specialized context

`:Agents send` offers providers that apply to the captured source buffer.
You can also send them directly:

- In a help window: `:Agents send help` sends the tag under the cursor and the
  surrounding section. If the cursor is on ordinary text, it uses the section's
  nearest tag. It does not follow a help link to another page.
- In a `:checkhealth` window: `:Agents send checkhealth` sends its contents.
- In an ordinary terminal: `:Agents send terminal` sends the last 200 lines,
  after trimming trailing blank lines.
- Anywhere with message history: `:Agents send messages` sends `:messages`.

The context picker omits unavailable entries. Sending from an agents session
uses the previous non-session window as its source, as usual.

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
belongs to an agents session. The limit must be a positive integer. It does
not change the registered provider's 200-line default.
