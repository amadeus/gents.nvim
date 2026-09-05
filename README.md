# agents.nvim

A Neovim plugin for running multiple agent CLI sessions and sending editor
context to them. The working module name is `agents`.

Phase 0 provides the scaffold, test harness, and CI configuration. Session
commands and `setup()` arrive in Phase 1.

Docs coming soon. The Neovim help placeholder is [doc/agents.txt](doc/agents.txt).

- [Design](AGENTS_CLI_DESIGN.md)
- [Build plan and progress](AGENTS_CLI_PLAN.md)
- [sidekick.nvim research](RESEARCH_SIDEKICK_NVIM.md)
- [RobertTLange/agents.nvim research](RESEARCH_AGENTS_NVIM.md)

Development targets Neovim stable, with nightly also tested in CI.

```sh
make test
make lint
```

`make test` requires Neovim, Make, curl, and tar. The first run downloads a
pinned [mini.test](https://github.com/nvim-mini/mini.test) revision into
`.deps/`; later runs use that local copy. Tests use isolated directories
under `.test/`. Neither directory is tracked. The plugin has no runtime
dependencies.

`make lint` requires StyLua 2.5.2. Override the executables when needed:

```sh
make test NVIM=/path/to/nvim
make lint STYLUA=/path/to/stylua
```

For an interactive clean load from the repository root:

```sh
nvim --clean -u tests/minimal_init.lua
```
