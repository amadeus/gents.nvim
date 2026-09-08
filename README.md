# Agents.nvim

Agents.nvim brings CLI agents into your existing Neovim workflow, running the
tools you're already familiar with in native terminal buffers.

- Run multiple agent sessions, including multiple instances of the same tool.
  Show them in splits, floating windows, tabs, or your current window, and hide
  them while they keep working.
- Share context directly from Neovim: file and line references, selected text,
  diagnostics, buffer contents, and terminal buffer scrollback.
- React to agent lifecycle events with autocmds, including custom notifications
  when an agent is ready for input.
- Fit agents into your own workflow with composable commands and Lua APIs for
  your keymaps, scripts, and pickers.

Our goal was not to re-invent the agentic workflow, just make it feel like a
first class citizen inside of neovim.

## Installation

Use Neovim 0.12+ and install the agent CLIs you want to use separately. Their
commands must be available on your `PATH`. Git is needed to install the plugin.

Choose one installation method. Each example includes a minimal configuration
and keymaps you can customize. The mappings use Normal mode; sending context
also works with a Visual selection. agents.nvim installs no mappings by default.

### lazy.nvim

Add this to your [lazy.nvim](https://lazy.folke.io/spec) plugin specs:

```lua
{
  "amadeus/agents.nvim",
  cmd = "Agents",
  opts = {
    -- By default, sessions open in a full-height vertical split on the right.
    -- If you'd prefer, you can use a floating window instead.
    -- layout = "float",
    -- Optional: a 60-column float near the top-right corner.
    -- float = {
    --   width = 60,
    --   height = vim.o.lines - 4,
    --   row = 0,
    --   border = "rounded",
    --   anchor = "NE",
    --   col = vim.o.columns - 2,
    -- },
  },
  keys = {
    -- Pick a CLI tool and start a new session.
    { "<leader>an", "<cmd>Agents new<cr>", desc = "New session" },
    -- Choose a command, such as starting, hiding, or closing a session.
    { "<leader>ac", "<cmd>Agents actions<cr>", desc = "Agents actions" },
    -- Show or hide a session without stopping its CLI.
    { "<leader>aa", "<cmd>Agents toggle<cr>", desc = "Toggle session" },
    -- Choose context to send, including selected text in Visual mode.
    { "<leader>as", "<cmd>Agents send<cr>", mode = { "n", "x" }, desc = "Send context", },
  },
}
```

### Neovim's built-in package manager

Add this to your `init.lua` using [vim.pack](https://neovim.io/doc/user/pack/):

```lua
vim.pack.add({ "https://github.com/amadeus/agents.nvim" })
require("agents").setup({
  -- By default, sessions open in a full-height vertical split on the right.
  -- If you'd prefer, you can use a floating window instead.
  -- layout = "float",
  -- Optional: a 60-column float near the top-right corner.
  -- float = {
  --   width = 60,
  --   height = vim.o.lines - 4,
  --   row = 0,
  --   border = "rounded",
  --   anchor = "NE",
  --   col = vim.o.columns - 2,
  -- },
  keys = {
    -- Pick a CLI tool and start a new session.
    { "<leader>an", "new", mode = "n" },
    -- Choose a command, such as starting, hiding, or closing a session.
    { "<leader>ac", "actions", mode = "n" },
    -- Show or hide a session without stopping its CLI.
    { "<leader>aa", "toggle", mode = "n" },
    -- Choose context to send, including selected text in Visual mode.
    { "<leader>as", "send", mode = { "n", "x" } },
  },
})
```

<details>
<summary>vim-plug</summary>

Add this inside your existing [vim-plug](https://github.com/junegunn/vim-plug)
`plug#begin()` / `plug#end()` block:

```vim
Plug 'amadeus/agents.nvim'
```

Reload your configuration or restart Neovim, then run `:PlugInstall`.
After installation, add this after `plug#end()` in `init.vim`, then restart
Neovim:

```vim
lua << EOF
require("agents").setup({
  -- By default, sessions open in a full-height vertical split on the right.
  -- If you'd prefer, you can use a floating window instead.
  -- layout = "float",
  -- Optional: a 60-column float near the top-right corner.
  -- float = {
  --   width = 60,
  --   height = vim.o.lines - 4,
  --   row = 0,
  --   border = "rounded",
  --   anchor = "NE",
  --   col = vim.o.columns - 2,
  -- },
  keys = {
    -- Pick a CLI tool and start a new session.
    { "<leader>an", "new", mode = "n" },
    -- Choose a command, such as starting, hiding, or closing a session.
    { "<leader>ac", "actions", mode = "n" },
    -- Show or hide a session without stopping its CLI.
    { "<leader>aa", "toggle", mode = "n" },
    -- Choose context to send, including selected text in Visual mode.
    { "<leader>as", "send", mode = { "n", "x" } },
  },
})
EOF
```

</details>

Run `:Agents` once to ensure the plugin is loaded and open its picker. Then use
`:checkhealth agents` to check your setup.

## Configuration

By default, sessions open in a full-height vertical split on the right
(`layout = "botright vsplit"`). Showing a session that already has a window
focuses that window.

For floating windows by default, uncomment `layout = "float"` in your
configuration above. The optional `float` example sets the window's size and
position. With lazy.nvim, these settings live inside `opts`.

agents.nvim uses Neovim's `vim.ui.select` picker by default. If you have
[snacks.nvim](https://github.com/folke/snacks.nvim) installed, add
`picker = "snacks"` to the same options table for its menus and extra shortcuts.
See [layouts and picker shortcuts](docs/usage.md#choose-where-sessions-open)
for split, tab, current-window, and float settings.

## Commands

| Command                     | What it does                                                            |
| --------------------------- | ----------------------------------------------------------------------- |
| `:Agents` or `:Agents pick` | Choose an existing session, or start one if none exist.                 |
| `:Agents actions`           | Open a menu to start or manage sessions, switch focus, or send context. |
| `:Agents new`               | Pick a CLI tool and start a session.                                    |
| `:Agents new claude`        | Start a Claude session directly.                                        |
| `:Agents focus`             | Focus a session, or return to the previous window when called from one. |
| `:Agents toggle`            | Show or hide the selected session in the current tab.                   |
| `:Agents hide`              | Hide the selected session's windows and keep its CLI running.           |
| `:Agents close`             | Stop the selected CLI and delete its buffer.                            |
| `:Agents send`              | Choose file references or text to send to an agent.                     |

Commands that need a session use the session in the current buffer, the only
session, or a picker if there are multiple sessions running. Specify an ID or
label to choose one directly. Commands also compose under `actions`:

```vim
:Agents actions hide claude #2
:Agents send file diagnostics --target claude #2
```

Sending context focuses the selected session so you can continue typing. Add
`--no-focus` to keep focus in your editor. See
[calling commands directly](docs/usage.md#call-commands-directly) for target
selection, ranges, and the Lua equivalents.

Generally speaking we recommend setting up keybinds to map back into these
actions or functions instead of calling them directly.

## Documentation

Use `:help agents.nvim` for the complete reference, or start with these guides:

- [Usage guide](docs/usage.md)
- [Sending context](docs/recipes/context.md)
- [Agent ready notifications](docs/recipes/ready.md)
- [Conversation titles](docs/recipes/titles.md)
- [Custom pickers](docs/recipes/pickers.md)
- [Statusline integration](docs/recipes/statusline.md)

## Development

You'll need Neovim, Make, curl, tar, StyLua 2.5.2, and LuaLS 3.19.1.
From the repository root:

```sh
make test
make lint
make typecheck
```

The first test run downloads mini.test into `.deps/`; generated test and
checker output stays in `.test/`. Pass `NVIM=/path/to/nvim` to use another
Neovim build. To include the Snacks integration tests, set `SNACKS_DIR` to
your snacks.nvim checkout when running `make test`.
