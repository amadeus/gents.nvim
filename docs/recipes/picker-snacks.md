# Snacks picker

After configuring [snacks.nvim](https://github.com/folke/snacks.nvim), add this
`picker` function to your agents.nvim setup. It uses Snacks' public picker
configuration and leaves agents.nvim independent of Snacks.

```lua
require("agents").setup({
  picker = function(spec)
    local items, actions, keys = {}, {}, {}
    local shortcuts = {
      vsplit = "<C-v>",
      split = "<C-x>",
      tabnew = "<C-t>",
      current = "<C-CR>",
      edit_args = "<C-e>",
      hide = "<C-h>",
      close = "<C-d>",
    }
    for index, item in ipairs(spec.items) do
      items[index] = {
        text = item.text,
        agents_index = index,
        preview = item.preview and { text = item.preview } or nil,
      }
    end
    for name, action in pairs(spec.actions) do
      local id = "agents_" .. name
      actions[id] = function(picker, item)
        if not item then
          return
        end
        picker:close()
        vim.schedule(function()
          action(spec.items[item.agents_index])
        end)
      end
      local key = name == spec.default and "<CR>" or shortcuts[name]
      if key then
        keys[key] = { id, mode = { "n", "i" }, desc = name }
      end
    end
    require("snacks").picker({
      title = spec.title,
      items = items,
      format = function(item)
        return { { item.text, spec.items[item.agents_index].hl } }
      end,
      preview = "preview",
      confirm = "agents_" .. spec.default,
      actions = actions,
      win = { input = { keys = keys }, list = { keys = keys } },
    })
  end,
})
```

Enter starts a tool or shows a session. Ctrl-V, Ctrl-X, Ctrl-T, and Ctrl-Enter
choose `vsplit`, `split`, `tabnew`, and `current`. These layouts apply when
opening a new view; an already visible session is focused in its existing
window. Ctrl-E edits a tool's full command. Ctrl-H hides a session and Ctrl-D
closes it, stopping its job. All shortcuts work in the input and list windows.
Ctrl-Enter requires a terminal that reports it as a distinct key; change the
`current` shortcut if needed.

The edit prompt splits text on whitespace. Quotes, shell variables, and shell
operators stay literal; use `agents.new("tool", { cmd = { ... } })` for argv
elements containing spaces. Canceling or submitting an empty command launches
nothing.

The adapter closes its picker before running the action, which lets the plugin
restore the invoking window. Only actions in the supplied spec get shortcuts.
With `picker = nil`, `vim.ui.select` still offers only Enter.

Verified against Snacks commit
[`882c996`](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/docs/picker.md).
To run the optional recipe integration tests against your installed copy:

```sh
SNACKS_DIR=/path/to/snacks.nvim make test
```
