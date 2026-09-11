# Oh My Pi

Use [Oh My Pi](https://omp.sh/) in a native Neovim terminal with gents.nvim's
session picker, context sends, and conversation titles. Install and authenticate
`omp` separately, then start it with:

```vim
:Gents new omp
```

The built-in tool runs `omp` without extra arguments. For one launch, pass CLI
options through Lua, for example to open OMP's conversation-resume picker:

```lua
require("gents").new("omp", { args = { "--resume" } })
```

## Send context

Use the ordinary [context commands and mappings](context.md). File references
use gents.nvim's default `@path`, `@path:line`, and `@path:start-end` text;
copied selections and buffers use Markdown code blocks. These are prompt text,
not CLI `@file` arguments that attach file contents during startup. Use
`selection` or `buffer` when you want to include the code itself.

OMP opens a menu when a paste reaches 100 lines by default. That menu can
intercept the Enter keystroke from `submit = true`. To put large context sends
directly into OMP's editor, merge this into `~/.omp/agent/config.yml` (or your
active profile's config):

```yaml
paste:
  largeMenuThreshold: 0
```

OMP may still show the pasted text as a compact attachment; it expands the
content when you submit. The setting disables the extra menu, not the content.

### Apply the setting only to gents.nvim sessions

Save the YAML above in a separate file, such as
`~/.config/nvim/omp-gents.yml`, then add an override to your existing setup:

```lua
require("gents").setup({
  tools = {
    omp = {
      cmd = { "omp", "--config", vim.fn.expand("~/.config/nvim/omp-gents.yml") },
    },
  },
})
```

OMP loads `--config` as a process-only overlay after its normal settings; the
file must exist. gents.nvim does not create or modify OMP configuration files.
See OMP's [configuration precedence](https://github.com/unsigned-gg/omp/blob/0c6c981ee5838d97700180383077eb0a3790637c/docs/config-usage.md)
and [paste settings](https://github.com/unsigned-gg/omp/blob/0c6c981ee5838d97700180383077eb0a3790637c/packages/coding-agent/src/config/settings-schema.ts).

## Titles and notifications

gents.nvim removes OMP's brand and activity marker from terminal titles so
`π > Fix tests` and `π ⠋ Fix tests` both appear as `Fix tests`. See
[conversation titles](titles.md).

OMP enables completion and ask notifications by default, but their transport
depends on terminal detection. A bell does not trigger `GentsReady`. If native
notifications do not reach Neovim, use the [OMP ready extension](ready.md#oh-my-pi)
for completed responses. The recipe also explains avoiding duplicate events.
