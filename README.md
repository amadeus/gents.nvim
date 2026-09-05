# agents.nvim

A Neovim plugin for running multiple agent CLI sessions and sending editor
context to them. The working module name is `agents`.

Phase 1 supports multiple sessions per tool, native terminal buffers,
configurable layouts, and tool/session pickers through `vim.ui.select`.

Docs coming soon. The Neovim help placeholder is [doc/agents.txt](doc/agents.txt).

```lua
require("agents").setup({
  layout = "vsplit",
  on_exit = "keep",
  tools = {
    grok = false,
    -- Custom tools use argv lists:
    shell = { cmd = { "sh" } },
  },
})
```

Setup is optional. `:Agents new` picks a tool; `:Agents new claude` starts
one directly. Extra words are passed as literal arguments, split on
whitespace. `:Agents toggle` hides the current session or shows/picks one;
`:Agents pick` always opens a picker. `:Agents hide` keeps the job running,
and `:Agents close` stops it. Both accept an optional session id or label,
such as `:Agents close claude #2`. Bare `:Agents` opens the picker.

```lua
local agents = require("agents")
local session = agents.new("claude", { layout = "tabnew", label = "review" })
agents.hide(session.id)
agents.show("review", { layout = "float" })
agents.close(session.id)
```

`agents.sessions()` lists sessions and `agents.current()` returns the session
in the current window. `show`, `hide`, and `close` accept an id, exact label,
or filter function. Without a target they use the current session, the only
one visible in this tab, the only session overall, or a picker, in that order.

Hidden sessions remain unlisted. Successful exits can be removed automatically
with `on_exit = "close"`; failed exits remain available for inspection.
No keymaps are installed. Context sending, configured keys, events, and
additional picker actions arrive in later phases.

Development targets Neovim stable, with nightly also tested in CI.

```sh
make test
make lint
make typecheck
```

`make test` requires Neovim, Make, curl, and tar. The first run downloads a
pinned [mini.test](https://github.com/nvim-mini/mini.test) revision into
`.deps/`; later runs use that local copy. Tests use isolated directories
under `.test/`. Neither directory is tracked. The plugin has no runtime
dependencies.

`make lint` requires StyLua 2.5.2. `make typecheck` requires
[LuaLS 3.19.1](https://github.com/LuaLS/lua-language-server/releases/tag/3.19.1),
the version pinned in CI. LuaCATS annotations provide editor completion and
static checks without changing the plugin's Lua runtime.

The typecheck uses the selected Neovim's runtime definitions and checks plugin
code and development scripts. It excludes runtime tests, which intentionally
exercise invalid inputs, and local editor configuration. Generated configuration
and LuaLS files stay under `.test/typecheck/`; editor diagnostics still use
`.luarc.json`. Warnings and errors fail the check.
Table-shape checking is enabled, and implicit `number`-to-`integer` assignments
are rejected. Unknown inferred types, incomplete function signatures, and
missing annotations on global or exported local functions are also checked.
These diagnostics supplement explicit annotations; LuaLS does not provide
a `noImplicitAny` guarantee.

Override the executables when needed:

```sh
make test NVIM=/path/to/nvim
make lint STYLUA=/path/to/stylua
make typecheck NVIM=/path/to/nvim LUA_LS=/path/to/lua-language-server
```

For an interactive clean load from the repository root:

```sh
nvim --clean -u tests/minimal_init.lua
```
