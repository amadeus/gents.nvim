# Contributing to agents.nvim

agents.nvim runs CLI agents in native Neovim terminal buffers. It provides
session management, pickers, context sharing, and composable commands and Lua
APIs. The CLI owns the conversation; the plugin integrates it into the editor.
The supported baseline is Neovim 0.12+ with LuaJIT.

`CLAUDE.md` imports this file. Keep shared instructions here.

## Working with the checkout

- Never stage, unstage, or commit without an explicit user request. If the
  index changes during your work, assume the user is working in parallel and
  leave it alone. Earlier permission for a different task does not carry over.
- Read the current files and diff before editing. Preserve unrelated changes
  and the user's wording. Keep fixes scoped to the requested task.
- Some checkouts contain local plan, design, and research files. Keep those
  files in the root and untracked; do not move them into public documentation.
  Contributor instructions and public docs must work without those files.
- When working through a plan, stop after the requested piece for review
  unless the user asks you to continue automatically.

## Code map

- `lua/agents/init.lua`: public Lua API; `plugin/agents.lua` and
  `lua/agents/commands.lua`: command registration, dispatch, and completion.
- `lua/agents/config.lua`, `tools.lua`, and `types.lua`: configuration,
  CLI definitions, and shared LuaLS contracts.
- `lua/agents/session.lua`, `window.lua`, and `target.lua`: session/job
  lifetime, window placement, and target selection.
- `lua/agents/picker.lua` and `pickers/`: picker specifications and adapters;
  `keys.lua`: optional session keymaps.
- `lua/agents/context.lua`, `providers.lua`, `render.lua`, and `send.lua`:
  capture source context, build content, and deliver it to a CLI.
- `lua/agents/events.lua`, `titles.lua`, and `buffer_names.lua`: lifecycle
  events, terminal signals, conversation titles, and buffer names.
- `tests/test_*.lua`: mini.test suites; `tests/helpers.lua`: shared runtime
  helpers; `tests/meta/`: test-library type definitions.

## Implementation conventions

- Sessions own buffers and jobs, not persistent window handles. Query windows
  when needed; capture the invoking window and context before deferred picker
  actions. One session buffer can appear in several windows.
- Preserve native buffer/window behavior and window-option history. Prefer
  existing Neovim APIs over custom state, layout enforcement, or workarounds.
- Keep picker actions available through commands or Lua APIs. Keep optional
  integrations optional and keymaps opt-in.
- Use the plural `agents` namespace for plugin identifiers. A tool is a CLI
  definition; a session is one running instance or its retained terminal buffer.
- Follow `stylua.toml`: LuaJIT syntax, two-space indentation, 100-column
  formatting, and double quotes where appropriate.
- Annotate function parameters, return values, and tables where needed for
  LuaLS inference. Reuse existing contracts and check optional values before
  using them. Fix diagnostics at their source; do not add blanket suppressions
  or use `any` and casts merely to silence the checker.
- `.luarc.json` enables strict table shapes, rejects implicit number-to-integer
  assignments, and treats `no-unknown` as an error. Keep these checks enabled.
- Comments explain intent or non-obvious behavior, not the history of an edit.

## Validation

Run checks from the repository root. Development dependencies are listed in
the README; versions used by CI are in `.github/workflows/ci.yml`.

| Command            | Purpose                                           |
| ------------------ | ------------------------------------------------- |
| `make test`        | Run headless Neovim tests with mini.test.         |
| `make lint`        | Check Lua formatting with StyLua.                 |
| `make typecheck`   | Run the LuaLS CLI checker against code and tests. |
| `git diff --check` | Check patch whitespace.                           |

Use `make test NVIM=/path/to/nvim` to select a Neovim executable; the same
override works for `make typecheck`. Run
`SNACKS_DIR=/path/to/snacks.nvim make test` to include Snacks integration
coverage, `MINI_PICK_DIR=/path/to/mini.pick make test` for mini.pick,
`TELESCOPE_DIR=... PLENARY_DIR=... make test` for Telescope, and
`FZF_LUA_DIR=... FZF_BIN=... make test` for fzf-lua. The first test run
downloads mini.test into `.deps/`; generated test and checker output belongs in
`.test/`.

For Lua changes, run tests, formatting, and type checking. Add regression
coverage for changed behavior using the existing suites and helpers. Lifecycle
tests should use real lightweight jobs such as `cat` or `sh`, without requiring
an authenticated agent CLI. Restore changed options, globals, and stubs after
tests. Clean up jobs, buffers, and temporary files; use `vim.fn.tempname()` and
canonicalize paths with `vim.uv.fs_realpath()` when comparing them.

For prose-only edits, check the affected links, examples, and formatting; a full
runtime test run is unnecessary. Do not build LuaLS diagnostic harnesses inside
Neovim: use `make typecheck`, and let the user confirm editor-specific issues.
Report checks that could not run and remove temporary investigation artifacts.

## Documentation

- Keep README a quick start. `doc/agents.txt` is the complete public reference;
  `docs/usage.md` explains everyday workflows; `docs/recipes/` shows practical
  integrations. Keep overlapping descriptions and links consistent.
- Introduce what a feature does and why someone would use it before listing
  options or types. Explain defaults and optional setup clearly, with concrete
  actions and visible results.
- Document the plugin as it works now. Omit phase tracking, migration notes
  about unreleased development changes, abandoned approaches, and test history.
- Call the plugin `agents.nvim`; use "agents" for actual CLI agents. Preserve
  names such as `:Agents`, `require("agents")`, and `AgentsReady`.
- Verify behavior against current source. Update relevant docs alongside public
  API changes, and verify external API examples against upstream references.
  Investigate tool-specific readiness or title issues when requested; do not
  expand a docs task into proactive CLI integration work.
