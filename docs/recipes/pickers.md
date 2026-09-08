# Use your preferred picker

Use your usual picker for agents.nvim menus. By default, the plugin calls
`vim.ui.select`, so an existing replacement for that function also handles
`:Agents actions`, `:Agents new`, `:Agents pick`, and `:Agents send`. Leave the
agents.nvim `picker` option unset to use it.

That is enough to choose an item and run the menu's default action: execute an
action, start a tool, choose a session, or send context. Cancelling does
nothing. For the built-in Snacks adapter and its additional shortcuts, see
[pickers and shortcuts](../usage.md#pickers-and-shortcuts). The built-in
mini.pick, Telescope, and fzf-lua adapters are described below.

The examples below assume the chosen picker plugin is installed and configured.
Choose one integration and merge its agents.nvim options into your existing
setup.

## fzf-lua with agents.nvim actions

agents.nvim includes an fzf-lua adapter. Install fzf-lua and the fzf
executable, then select the adapter:

```lua
require("agents").setup({ picker = "fzf-lua" })
```

Menus open with your fzf-lua window and keymaps, without a preview. Enter runs
the menu's default action. Press F1 for fzf-lua's help window, which lists the
additional agents.nvim actions by name:

| Key       | Help name             | Menus                 |
| --------- | --------------------- | --------------------- |
| Ctrl-V    | agents-open-in-vsplit | New Session, Sessions |
| Ctrl-S    | agents-open-in-split  | New Session, Sessions |
| Ctrl-T    | agents-open-in-tab    | New Session, Sessions |
| Alt-F     | agents-open-in-float  | New Session, Sessions |
| Alt-Enter | agents-open-here      | New Session, Sessions |
| Alt-E     | agents-edit-command   | New Session           |
| Alt-H     | agents-hide-session   | Sessions              |
| Ctrl-X    | agents-close-session  | Sessions              |

The keys above are bound only where your fzf-lua keymaps leave them free, and
the help window always shows the actual bindings. See `:help agents-picker-fzf`
for the complete behavior.

If you prefer fzf-lua's `register_ui_select()` and leave `picker` unset,
agents.nvim menus still open in fzf-lua with each menu's default action only.

## mini.pick with agents.nvim actions

agents.nvim includes a mini.pick adapter. Set up mini.pick first, then select
the adapter:

```lua
require("mini.pick").setup()
require("agents").setup({ picker = "mini" })
```

Menus open with your mini.pick window, matching, and navigation. Enter runs the
menu's default action. Press Shift-Tab in a menu to open mini.pick's info view,
which lists the additional agents.nvim actions under "Mappings (custom)":

| Key        | Info view name         | Menus                 |
| ---------- | ---------------------- | --------------------- |
| Ctrl-V     | Agents open in vsplit  | New Session, Sessions |
| Ctrl-S     | Agents open in split   | New Session, Sessions |
| Ctrl-T     | Agents open in tabpage | New Session, Sessions |
| Alt-F      | Agents open in float   | New Session, Sessions |
| Ctrl-Enter | Agents open here       | New Session, Sessions |
| Ctrl-E     | Agents edit command    | New Session           |
| Alt-H      | Agents hide session    | Sessions              |
| Ctrl-D     | Agents close session   | Sessions              |

The vsplit, split, and tabpage actions use your `choose_in_vsplit`,
`choose_in_split`, and `choose_in_tabpage` keys. The other keys are bound only
where your mini.pick configuration leaves them free, and the info view always
shows the actual bindings. Menus have no preview. See `:help agents-picker-mini`
for the complete behavior.

`mini.pick.setup()` also installs a `vim.ui.select` replacement. If you keep it
and leave `picker` unset, agents.nvim menus still open in mini.pick with each
menu's default action only.

## Telescope with agents.nvim actions

agents.nvim includes a Telescope adapter. Install telescope.nvim with its
plenary.nvim dependency, then select the adapter:

```lua
require("agents").setup({ picker = "telescope" })
```

Menus open with your Telescope layout, sorting, and mappings, without a preview
pane. Enter runs the menu's default action. Press Ctrl-/ in Insert mode or `?`
in Normal mode for Telescope's key hints, which list the additional agents.nvim
actions by name:

| Key        | Help name             | Menus                 |
| ---------- | --------------------- | --------------------- |
| Ctrl-V     | agents_open_in_vsplit | New Session, Sessions |
| Ctrl-X     | agents_open_in_split  | New Session, Sessions |
| Ctrl-T     | agents_open_in_tab    | New Session, Sessions |
| Ctrl-F     | agents_open_in_float  | New Session, Sessions |
| Ctrl-Enter | agents_open_here      | New Session, Sessions |
| Ctrl-E     | agents_edit_command   | New Session           |
| Alt-H      | agents_hide_session   | Sessions              |
| Ctrl-D     | agents_close_session  | Sessions              |

Keys you have bound to Telescope's `select_horizontal`, `select_vertical`, and
`select_tab` actions run the same split, vsplit, and tab actions. The keys above
are bound only where your Telescope `defaults.mappings` leave them free, and the
key hints always show the actual bindings. See `:help agents-picker-telescope`
for the complete behavior.

## Extend an adapter

An adapter receives `spec.title`, `spec.items`, `spec.actions`, and `spec.default`.
Display an item's `text` and pass that same item to the chosen action. Use
`spec.default` because the default differs between menus. Close your picker
before invoking the action, and invoke nothing on cancellation.

Items can also supply previews and styled chunks, and menus expose additional
actions for an adapter to bind. See `:help agents-picker-custom` and
`:help agents.PickerSpec` in the [full help file](../../doc/agents.txt) for the
complete contract.
