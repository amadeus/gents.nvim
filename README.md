# agents.nvim

Run agent CLI sessions in native Neovim terminals. Keep multiple sessions open,
hide them while you edit, and bring them back when you need them.

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
    { "<leader>aa", "<cmd>Agents toggle<cr>", desc = "Toggle agents" },
    { "<leader>an", "<cmd>Agents new<cr>", desc = "New agent session" },
  },
}
```

Install the agent CLIs you want to use separately. The mappings above are
optional; the plugin installs none by default.

- `:Agents new` — pick a tool and start a session.
- `:Agents new claude` — start Claude directly.
- `:Agents toggle` — hide the current session or bring one back.
- `:Agents pick` — choose a session.
- `:Agents close` — stop and remove a session.

Hidden sessions keep running. Run `:checkhealth agents` to check your setup.
For a custom picker, see the [Snacks recipe](docs/recipes/picker-snacks.md).

For development, run these from the repository root:

```sh
make test
make lint
make typecheck
```

You'll need Neovim, Make, curl, tar, StyLua 2.5.2, and LuaLS 3.19.1. The first
test run downloads mini.test into `.deps/`; test and typecheck output stays in
`.test/`. To use another Neovim version, pass `NVIM=/path/to/nvim` to Make.
