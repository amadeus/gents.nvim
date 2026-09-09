# Use your preferred picker

gents.nvim opens four menus: Actions, New Session, Sessions, and Send Context.
By default they use `vim.ui.select`, so an existing replacement for that
function already handles `:Gents actions`, `:Gents new`, `:Gents pick`, and
`:Gents send`. Leave the `picker` option unset to use it. That is enough to
choose a row and run the menu's default action; cancelling does nothing.

A built-in adapter adds the other actions: place a session in a vertical or
horizontal split, a new tab, a float, or the current window, edit the launch
command, and hide or close a session. Every adapter offers the same actions
where a menu supplies them, on keys that fit its picker, and each picker's
native help lists the actual bindings.

| `picker`      | Plugin                                                                                                                                                   | Native help         |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| `"snacks"`    | [folke/snacks.nvim](https://github.com/folke/snacks.nvim)                                                                                                | `?`, plus a footer  |
| `"mini"`      | [nvim-mini/mini.pick](https://github.com/nvim-mini/mini.pick)                                                                                            | Shift-Tab info view |
| `"telescope"` | [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) with [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | Ctrl-/ or `?`       |
| `"fzf-lua"`   | [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua) with the fzf executable                                                                          | F1                  |

Install the plugin yourself and add the option to your existing gents.nvim
setup. Selecting an adapter whose plugin is missing reports an error when a menu
opens; `:checkhealth gents` shows the same result. The Snacks adapter is
covered in [pickers and shortcuts](../usage.md#pickers-and-shortcuts); the
others follow. A key your picker configuration already uses is never overridden,
so check the native help if a key listed here does nothing.

## mini.pick

Set up mini.pick first, then select the adapter:

```lua
require("mini.pick").setup()
require("gents").setup({ picker = "mini" })
```

Menus open with your mini.pick window, matching, and navigation, without a
preview. Enter runs the menu's default action. Press Shift-Tab in a menu to open
mini.pick's info view, which lists the additional actions under "Mappings
(custom)":

| Key        | Info view name         | Menus                 |
| ---------- | ---------------------- | --------------------- |
| Ctrl-V     | Gents open in vsplit   | New Session, Sessions |
| Ctrl-S     | Gents open in split    | New Session, Sessions |
| Ctrl-T     | Gents open in tabpage  | New Session, Sessions |
| Alt-F      | Gents open in float    | New Session, Sessions |
| Ctrl-Enter | Gents open here        | New Session, Sessions |
| Ctrl-E     | Gents edit command     | New Session           |
| Alt-H      | Gents hide session     | Sessions              |
| Ctrl-D     | Gents close session    | Sessions              |

The vsplit, split, and tabpage actions use your `choose_in_vsplit`,
`choose_in_split`, and `choose_in_tabpage` keys. See `:help gents-picker-mini`
for the complete behavior.

`mini.pick.setup()` also installs a `vim.ui.select` replacement. If you keep it
and leave `picker` unset, gents.nvim menus still open in mini.pick with each
menu's default action only.

## Telescope

Install telescope.nvim with its plenary.nvim dependency, then select the
adapter:

```lua
require("gents").setup({ picker = "telescope" })
```

Menus open with your Telescope layout, sorting, and mappings, without a preview
pane. Enter runs the menu's default action. Press Ctrl-/ in Insert mode or `?`
in Normal mode for Telescope's key hints, which list the additional actions by
name:

| Key        | Help name             | Menus                 |
| ---------- | --------------------- | --------------------- |
| Ctrl-V     | gents_open_in_vsplit  | New Session, Sessions |
| Ctrl-X     | gents_open_in_split   | New Session, Sessions |
| Ctrl-T     | gents_open_in_tab     | New Session, Sessions |
| Ctrl-F     | gents_open_in_float   | New Session, Sessions |
| Ctrl-Enter | gents_open_here       | New Session, Sessions |
| Ctrl-E     | gents_edit_command    | New Session           |
| Alt-H      | gents_hide_session    | Sessions              |
| Ctrl-D     | gents_close_session   | Sessions              |

Keys you have bound to Telescope's `select_horizontal`, `select_vertical`, and
`select_tab` actions run the same split, vsplit, and tab actions. See `:help
gents-picker-telescope` for the complete behavior.

## fzf-lua

Install fzf-lua and the fzf executable, then select the adapter:

```lua
require("gents").setup({ picker = "fzf-lua" })
```

Menus open with your fzf-lua window and keymaps, without a preview. Enter runs
the menu's default action. Press F1 for fzf-lua's help window, which lists the
additional actions by name:

| Key       | Help name             | Menus                 |
| --------- | --------------------- | --------------------- |
| Ctrl-V    | gents-open-in-vsplit  | New Session, Sessions |
| Ctrl-S    | gents-open-in-split   | New Session, Sessions |
| Ctrl-T    | gents-open-in-tab     | New Session, Sessions |
| Alt-F     | gents-open-in-float   | New Session, Sessions |
| Alt-Enter | gents-open-here       | New Session, Sessions |
| Alt-E     | gents-edit-command    | New Session           |
| Alt-H     | gents-hide-session    | Sessions              |
| Ctrl-X    | gents-close-session   | Sessions              |

The vsplit, split, and tab keys are the ones fzf-lua uses for files; the rest
avoid fzf's own editing and scrolling bindings. See `:help gents-picker-fzf`
for the complete behavior.

If you prefer fzf-lua's `register_ui_select()` and leave `picker` unset,
gents.nvim menus still open in fzf-lua with each menu's default action only.

## Custom adapters

Set `picker` to a function to drive any other UI. The adapter receives a spec
with `title`, `items`, `actions`, and `default`. Display each item's `text`, and
pass the same item to the chosen action. Use `spec.default` because the default
action differs between menus. Close your picker before invoking the action, and
invoke nothing on cancellation.

This complete adapter reproduces the default behavior through `vim.ui.select`:

```lua
require("gents").setup({
  picker = function(spec)
    vim.ui.select(spec.items, {
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

Items can also supply previews and styled chunks, and menus expose the
additional actions for an adapter to bind. See `:help gents-picker-custom` and
`:help gents.PickerSpec` in the [full help file](../../doc/gents.txt) for the
complete contract.
