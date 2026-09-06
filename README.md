# agents.nvim

Run agent CLI sessions in native Neovim terminals. Keep multiple sessions open,
hide them while you edit, and send file references, selected text, or diagnostics.

Add this to your [lazy.nvim](https://lazy.folke.io/spec) plugin specs:

```lua
{
  "amadeus/agents.nvim",
  cmd = "Agents",
  opts = {
    layout = "vsplit", -- "split", "tabnew", "current", or "float"
    on_exit = "keep", -- "close" removes sessions that exit successfully
  },
  keys = {
    { "<leader>ac", "<cmd>Agents actions<cr>", desc = "Agents actions" },
    { "<leader>aa", "<cmd>Agents toggle<cr>", desc = "Toggle agents" },
    { "<leader>an", "<cmd>Agents new<cr>", desc = "New agent session" },
    { "<leader>as", function() require("agents").send() end, mode = { "n", "x" }, desc = "Send context" },
  },
}
```

Install the agent CLIs you want to use separately, and choose your own mappings.

- `:Agents new` — pick a tool and start a session.
- `:Agents new claude` — start Claude directly.
- `:Agents actions` — choose a top-level command.
- `:Agents toggle` — show or hide a selected session in the current tab.
- `:Agents pick` — choose an agent session.
- `:Agents focus` — focus an agent session or return to the previous window, keeping it open.
- `:Agents send` — choose context to send to a session.
- `:Agents send file diagnostics` — send a file reference and its diagnostics.
- `:Agents close` — stop and remove a session.

Supply choices to skip pickers: `:Agents actions hide codex #2` or
`:Agents send file --target codex #2`. See [commands](docs/commands.md) for
target selection, completion, and ranges.

Sending context focuses the selected agent by default.
Use `:Agents send file --no-focus` to keep focus in the originating window.

Hidden sessions keep running. Use `:checkhealth agents` to check your setup.
Set `picker = "snacks"` in `opts` to use the built-in Snacks picker
and its shortcuts (requires snacks.nvim).
See [sending context](docs/recipes/context.md) for file references, copied text,
and specialized providers. To react when a tool finishes, see
[agent ready notifications](docs/recipes/ready.md).
Tools that emit terminal titles show them in session pickers and status data;
see [conversation titles](docs/recipes/titles.md) for setup and limitations.

For development, run these from the repository root:

```sh
make test
make lint
make typecheck
```

You'll need Neovim, Make, curl, tar, StyLua 2.5.2, and LuaLS 3.19.1. The first
test run downloads mini.test into `.deps/`; test and typecheck output stays in
`.test/`. To use another Neovim version, pass `NVIM=/path/to/nvim` to Make.
