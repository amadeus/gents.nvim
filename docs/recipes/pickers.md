# Use your preferred picker

Use your usual picker for agents.nvim menus. By default, the plugin calls
`vim.ui.select`, so an existing replacement for that function also handles
`:Agents actions`, `:Agents new`, `:Agents pick`, and `:Agents send`. Leave the
agents.nvim `picker` option unset to use it.

That is enough to choose an item and run the menu's default action: execute an
action, start a tool, choose a session, or send context. Cancelling does nothing.
For the built-in Snacks adapter and its additional shortcuts, see
[pickers and shortcuts](../usage.md#pickers-and-shortcuts).

The examples below assume the chosen picker plugin is installed and configured.
Choose one integration and merge its agents.nvim options into your existing
setup.

## fzf-lua through vim.ui.select

Register fzf-lua once to use its search interface for agents.nvim and other
plugins that call `vim.ui.select`:

```lua
require("fzf-lua").register_ui_select()
```

Leave agents.nvim's `picker` unset, then run `:Agents pick`. This integration
supports the default action for each menu. It does not add agents.nvim's
placement, hide, close, or argument-editing shortcuts. Registration is a public
[fzf-lua API](https://github.com/ibhagwan/fzf-lua#neovim-api).

## mini.pick for agents.nvim menus

`mini.pick.setup()` already installs a `vim.ui.select` replacement. If you keep
that replacement, agents.nvim uses it without further configuration. To use
mini.pick for agents.nvim while another plugin handles your other selection
menus, provide an adapter that calls `MiniPick.ui_select` directly:

```lua
require("agents").setup({
  picker = function(spec)
    MiniPick.ui_select(spec.items, {
      prompt = spec.title,
      format_item = function(item)
        return item.text
      end,
    }, function(item)
      if item then
        spec.actions[spec.default](item)
      end
    end)
  end,
})
```

Run this after your mini.pick setup. It supports each menu's default action and
cancellation; it does not expose additional agents.nvim actions or context
previews. The callback receives the original item after mini.pick returns to its
target window. See the [MiniPick.ui_select
documentation](https://nvim-mini.org/mini.nvim/doc/mini-pick.html).

## Telescope with placement actions

A custom Telescope adapter lets you search agents.nvim rows and choose a split
or tab when opening a session. This example retains each original item in
`entry.value`, then closes Telescope before running the agents.nvim action:

```lua
require("agents").setup({
  picker = function(spec)
    local actions = require("telescope.actions")
    local action_set = require("telescope.actions.set")
    local state = require("telescope.actions.state")
    local opts = {}

    require("telescope.pickers").new(opts, {
      prompt_title = spec.title,
      finder = require("telescope.finders").new_table({
        results = spec.items,
        entry_maker = function(item)
          return { value = item, display = item.text, ordinal = item.text }
        end,
      }),
      sorter = require("telescope.config").values.generic_sorter(opts),
      previewer = false,
      attach_mappings = function(prompt_bufnr)
        local names = {
          default = spec.default,
          horizontal = "split",
          vertical = "vsplit",
          tab = "tabnew",
        }
        action_set.select:replace(function(_, kind)
          local action = spec.actions[names[kind]]
          local entry = state.get_selected_entry()
          if not action or not entry then
            return
          end
          local item = entry.value
          actions.close(prompt_bufnr)
          vim.schedule(function()
            action(item)
          end)
        end)
        return true
      end,
    }):find()
  end,
})
```

Enter runs `spec.default`. Telescope's horizontal, vertical, and tab selection
actions run agents.nvim's `split`, `vsplit`, and `tabnew` actions where available:
the New Session and Sessions menus. In other menus those actions do nothing. The
adapter replaces the whole selection action set so those bindings route through
agents.nvim instead of trying to open a row as a file.

This example has no context preview, float/current placement, hide, close, or
argument-editing bindings. Telescope's regular cancellation still closes the
picker without choosing. Its [developer guide](https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md)
explains entry makers and replacing actions; the
[selection action set](https://github.com/nvim-telescope/telescope.nvim/blob/master/lua/telescope/actions/set.lua)
groups the default, split, and tab selections.

## Extend an adapter

An adapter receives `spec.title`, `spec.items`, `spec.actions`, and `spec.default`.
Display an item's `text` and pass that same item to the chosen action. Use
`spec.default` because the default differs between menus. Close your picker
before invoking the action, and invoke nothing on cancellation.

Items can also supply previews and styled chunks, and menus expose additional
actions for an adapter to bind. See `:help agents-picker-custom` and
`:help agents.PickerSpec` in the [full help file](../../doc/agents.txt) for the
complete contract.
