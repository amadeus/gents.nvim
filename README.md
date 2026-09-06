# agents.nvim

Run agent CLI sessions in native Neovim terminals. Keep multiple sessions open,
hide them while you edit, and send them files, selections, or diagnostics.

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

Install the agent CLIs you want to use separately. The mappings above are
optional; the plugin installs none by default.

- `:Agents new` — pick a tool and start a session.
- `:Agents new claude` — start Claude directly.
- `:Agents actions` — choose a top-level command.
- `:Agents toggle` — hide the current session, hide visible sessions from an
  editor buffer, or show/select a session when none are visible (current tab).
- `:Agents pick` — choose a session.
- `:Agents send` — choose context to send to a session.
- `:Agents send file diagnostics` — send a file reference and its diagnostics.
- `:Agents close` — stop and remove a session.

Sends paste context without an extra Enter or a focus change by default.
Hidden sessions keep running. Run `:checkhealth agents` to check your setup.
For a custom picker, see the [Snacks recipe](docs/recipes/picker-snacks.md).
See [specialized context](docs/recipes/context.md) for help, health checks,
terminal scrollback, and message history. To react when a tool finishes, see
[agent ready notifications](docs/recipes/ready.md).

For development, run these from the repository root:

```sh
make test
make lint
make typecheck
```

You'll need Neovim, Make, curl, tar, StyLua 2.5.2, and LuaLS 3.19.1. The first
test run downloads mini.test into `.deps/`; test and typecheck output stays in
`.test/`. To use another Neovim version, pass `NVIM=/path/to/nvim` to Make.
