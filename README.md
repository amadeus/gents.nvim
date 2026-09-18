# Gents.nvim

Gents.nvim brings CLI agents into your existing Neovim workflow, running the
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
also works with a Visual selection. gents.nvim installs no mappings by default.

### lazy.nvim

Add this to your [lazy.nvim](https://lazy.folke.io/spec) plugin specs:

```lua
{
  "amadeus/gents.nvim",
  cmd = "Gents",
  opts = {
    -- By default, sessions open in a full-height vertical split on the right.
    -- If you'd prefer, you can use a floating window instead.
    -- layout = "float",
    -- Optional: a 60-column float near the top-right corner.
    -- float = {
    --   width = 60,
    --   height = function() return vim.o.lines - 4 end,
    --   row = 0,
    --   border = "rounded",
    --   anchor = "NE",
    --   col = function() return vim.o.columns - 1 end,
    -- },
  },
  keys = {
    -- Pick a CLI tool and start a new session.
    { "<leader>an", "<cmd>Gents new<cr>", desc = "New session" },
    -- Choose a command, such as starting, hiding, or closing a session.
    { "<leader>ac", "<cmd>Gents actions<cr>", desc = "Gents actions" },
    -- Show or hide a session without stopping its CLI.
    { "<leader>aa", "<cmd>Gents toggle<cr>", desc = "Toggle session" },
    -- Choose context to send, including selected text in Visual mode.
    { "<leader>as", "<cmd>Gents send<cr>", mode = { "n", "x" }, desc = "Send context", },
  },
}
```

### Neovim's built-in package manager

Add this to your `init.lua` using [vim.pack](https://neovim.io/doc/user/pack/):

```lua
vim.pack.add({ "https://github.com/amadeus/gents.nvim" })
require("gents").setup({
  -- By default, sessions open in a full-height vertical split on the right.
  -- If you'd prefer, you can use a floating window instead.
  -- layout = "float",
  -- Optional: a 60-column float near the top-right corner.
  -- float = {
  --   width = 60,
  --   height = function() return vim.o.lines - 4 end,
  --   row = 0,
  --   border = "rounded",
  --   anchor = "NE",
  --   col = function() return vim.o.columns - 1 end,
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
Plug 'amadeus/gents.nvim'
```

Reload your configuration or restart Neovim, then run `:PlugInstall`.
After installation, add this after `plug#end()` in `init.vim`, then restart
Neovim:

```vim
lua << EOF
require("gents").setup({
  -- By default, sessions open in a full-height vertical split on the right.
  -- If you'd prefer, you can use a floating window instead.
  -- layout = "float",
  -- Optional: a 60-column float near the top-right corner.
  -- float = {
  --   width = 60,
  --   height = function() return vim.o.lines - 4 end,
  --   row = 0,
  --   border = "rounded",
  --   anchor = "NE",
  --   col = function() return vim.o.columns - 1 end,
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

Run `:Gents` once to ensure the plugin is loaded and open its picker. Then use
`:checkhealth gents` to check your setup.

## Configuration

By default, sessions open in a full-height vertical split on the right
(`layout = "botright vsplit"`). Showing a session that already has a window
focuses that window.

For floating windows by default, uncomment `layout = "float"` in your
configuration above. The optional `float` example keeps the window near the
top-right corner as Neovim resizes. With lazy.nvim, these settings live inside
`opts`.

gents.nvim uses Neovim's `vim.ui.select` picker by default. If you have
[snacks.nvim](https://github.com/folke/snacks.nvim) installed, add
`picker = "snacks"` to the same options table for its menus and extra shortcuts.
Adapters for [mini.pick](https://github.com/nvim-mini/mini.pick),
[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), and
[fzf-lua](https://github.com/ibhagwan/fzf-lua) offer the same actions with
`picker = "mini"`, `"telescope"`, or `"fzf-lua"`. See
[pickers and shortcuts](docs/usage.md#pickers-and-shortcuts) and
[layouts](docs/usage.md#choose-where-sessions-open) for the details.

## Commands

| Command                   | What it does                                                            |
| ------------------------- | ----------------------------------------------------------------------- |
| `:Gents` or `:Gents pick` | Choose an existing session, or start one if none exist.                 |
| `:Gents actions`          | Open a menu to start or manage sessions, switch focus, or send context. |
| `:Gents new`              | Pick a CLI tool and start a session.                                    |
| `:Gents new claude`       | Start a Claude session directly.                                        |
| `:Gents focus`            | Focus a session, or return to the previous window when called from one. |
| `:Gents toggle`           | Hide visible sessions in the current tab, or summon a session.           |
| `:Gents hide`             | Hide the selected visible session's windows in the current tab.         |
| `:Gents close`            | Stop the selected CLI and delete its buffer.                            |
| `:Gents send`             | Choose file references or text to send to an agent.                     |

Commands that need a session use the session in the current buffer, the only
session, or a picker if there are multiple sessions running. Specify an ID or
label to choose one directly. Commands also compose under `actions`:

```vim
:Gents actions hide claude #2
:Gents send file diagnostics --target claude #2
```

Sending context focuses the selected session so you can continue typing. Add
`--no-focus` to keep focus in your editor. See
[calling commands directly](docs/usage.md#call-commands-directly) for target
selection, ranges, and the Lua equivalents.

Generally speaking we recommend setting up keybinds to map back into these
actions or functions instead of calling them directly.

## Documentation

Use `:help gents.nvim` for the complete reference, or start with these guides:

- [Usage guide](docs/usage.md)
- [Sending context](docs/recipes/context.md)
- [Agent ready notifications](docs/recipes/ready.md)
- [Conversation titles](docs/recipes/titles.md)
- [Oh My Pi setup](docs/recipes/omp.md)
- [Use your preferred picker](docs/recipes/pickers.md)
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
Neovim build. To include the picker integration tests, set `SNACKS_DIR` to
your snacks.nvim checkout, `MINI_PICK_DIR` to your mini.nvim or mini.pick
checkout, both `TELESCOPE_DIR` and `PLENARY_DIR` to your telescope.nvim and
plenary.nvim checkouts, or `FZF_LUA_DIR` to your fzf-lua checkout (with
`FZF_BIN` pointing at fzf when it is not on your PATH) when running
`make test`.

## Inspiration

Thanks to these plugins for the ideas that helped shape gents.nvim:

- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) — for managing
  CLI sessions and sharing editor context with agents.
- [RobertTLange/agents.nvim](https://github.com/RobertTLange/agents.nvim) — for
  keeping agent CLIs in native Neovim terminal buffers.
