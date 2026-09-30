# Copy conversation references

Copy a conversation from an agent buffer with `:Gents copy`, paste the reference
into your notes, then follow it with `require("gents").resume_at_cursor()`.
Enable `extend_gf = true` to follow these references with Normal-mode `gf`.
Use `:Gents copy --register +` for the clipboard or `--register a` for a named
register. The default unnamed register respects Neovim's `clipboard` option.

The CLI must report the actual conversation it is displaying. A requested
resume selector can be a name or prefix, so Gents keeps that selector separate
from the confirmed ID. Copying fails without changing registers until an ID
has been reported. No identity integration is installed automatically. The CLI
controls when history is saved and whether a copied selector can be restored.

## Reporting helper

The plugin includes `scripts/conversation.lua`. Find its absolute path with:

```vim
:lua print(vim.api.nvim_get_runtime_file("scripts/conversation.lua", false)[1])
```

Replace `/absolute/path/gents.nvim` in the examples below with the plugin's
installation directory. Use your Neovim executable's absolute path if `nvim`
is unavailable in CLI subprocesses. The helper reads JSON on stdin and sends
literal RPC arguments to the editor identified by `NVIM`, using `GENTS_SESSION`
to select the exact terminal. Outside Gents, it does nothing. It prints `{}`
and exits successfully even if the editor/session has closed, so a failed report
produces no hook decision or context.

Keep lifecycle reports synchronous and bound to the foreground conversation.
Do not report every server-wide session event or asynchronous turn completion:
those can arrive after the user switches conversations. Preserve the last ID
on normal exit, allowing retained buffers to copy it.

## Codex

Add this entry to the `hooks` object in `~/.codex/hooks.json`, preserving existing
hooks. Omit a matcher so startup, resume, clear, and compaction all report:

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "nvim --headless --clean -u NONE -i NONE -l /absolute/path/gents.nvim/scripts/conversation.lua",
        "timeout": 5
      }]
    }]
  }
}
```

Start a new Gents Codex terminal and review/trust this hook through Codex's
`/hooks` interface. Hooks must be enabled. The helper reads `session_id` and
ignores inputs carrying `agent_id`. See the [Codex hooks reference](https://learn.chatgpt.com/docs/hooks).

## Claude Code

Use Claude's foreground **status line**, which receives `session_id` at startup
and on session updates. SessionStart hooks can run in the background, including
for background forks, so they cannot reliably identify the conversation still
shown in the terminal. The status line cancels its previous script when a new
update arrives. See [status-line data and lifecycle](https://code.claude.com/docs/en/statusline)
and [SessionStart behavior](https://code.claude.com/docs/en/hooks#sessionstart).

Save this wrapper at an absolute path:

```sh
#!/bin/sh
input=$(cat)
printf '%s' "$input" | nvim --headless --clean -u NONE -i NONE \
  -l /absolute/path/gents.nvim/scripts/conversation.lua statusline >/dev/null 2>&1
# Preserve your existing status-line command and feed it the same JSON:
printf '%s' "$input" | sh /absolute/path/your-existing-statusline.sh
```

Configure the wrapper as your `statusLine.command` in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "sh /absolute/path/gents-statusline.sh"
  }
}
```

If you have no existing status line, replace the last line of the wrapper with
`printf 'Claude\n'`. Keep the helper before your display command so identity
reporting completes before expensive status-line work. Allow the status-line
update to finish before copying immediately after a switch.

## OpenCode v2

Track the foreground CLI route, including tab switches and forks. Create
`~/.config/opencode/cli-plugins/gents-conversation/tui.js`:

```js
import { execFileSync } from "node:child_process";
import { createEffect } from "solid-js";

export default {
  id: "gents-conversation.cli",
  setup(context) {
    if (!process.env.NVIM || !/^\d+$/.test(process.env.GENTS_SESSION ?? "")) return;
    return context.ui.slot({
      append: "app",
      render() {
        let previous;
        createEffect(() => {
          const route = context.ui.router.current();
          const identifier = route.type === "session" ? route.sessionID : null;
          if (identifier === previous) return;
          previous = identifier;
          try {
            execFileSync("nvim", [
              "--headless", "--clean", "-u", "NONE", "-i", "NONE", "-l",
              "/absolute/path/gents.nvim/scripts/conversation.lua", "report",
            ], {
              input: JSON.stringify(identifier ? { identifier } : { clear: true }),
              timeout: 2000,
              stdio: ["pipe", "ignore", "ignore"],
            });
          } catch {} // The editor may have closed.
        });
        return null;
      },
    });
  },
};
```

Add `"./cli-plugins/gents-conversation"` to `plugins` in
`~/.config/opencode/cli.json`. With `XDG_CONFIG_HOME`, use its `opencode/`
directory. The plugin must run in the CLI process that inherits the terminal's
environment. The home/new-conversation route clears the confirmed ID until a
session route is active. See [CLI plugin loading](https://opencode.ai/v2/docs/cli/plugins/)
and the [route and slot API](https://opencode.ai/v2/docs/build/plugins/cli/).

## Other built-in tools

These are identity integration paths, separate from launch-time resume support.
Only configure events that represent the foreground conversation. Tools and
versions can differ; check the linked contract for your installed CLI.

| Tool | Identity source and setup |
| --- | --- |
| Gemini | Configure a synchronous `SessionStart` command hook with the same JSON shape/command as Codex in `.gemini/settings.json`; it supplies `session_id`. [Reference](https://geminicli.com/docs/hooks/reference/). |
| Qwen | Configure the same synchronous `SessionStart` hook in `.qwen/settings.json`; `session_id` is supplied, subagent inputs carry `agent_id`. [Reference](https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/). |
| Copilot | Configure PascalCase `SessionStart` in `.github/hooks/gents.json`, with `version: 1` and a command entry using `type: "command"`, `bash: "<helper command>"`, and `timeoutSec: 5`. This format supplies `session_id` and `hook_event_name`. [Reference](https://docs.github.com/en/copilot/reference/hooks-reference). |
| Grok | The `superagent-ai/grok-cli` builtin supports the Codex-shaped `SessionStart` hook in `~/.grok/user-settings.json`. `session_id` is optional upstream; copy stays unavailable when it is absent. Other CLIs named Grok have different contracts. [Input types](https://github.com/superagent-ai/grok-cli/blob/main/src/hooks/types.ts). |
| Pi | An extension can report `ctx.sessionManager.getSessionId()` on `session_start`; current Pi repeats it after new/resume/fork. Only report persistent sessions (`getSessionFile()` is present), from the foreground UI. [Extension lifecycle](https://github.com/earendil-works/pi/blob/v0.85.1/packages/coding-agent/docs/extensions.md). |
| OMP | An extension can report the foreground context's `sessionManager.getSessionId()` on `session_start`, `session_switch`, and `session_branch`; check persistence and foreground UI first. [Lifecycle](https://github.com/unsigned-gg/omp/blob/main/docs/extensions.md). |
| Amp | `session.start` exposes `event.thread.id`, but events are thread-scoped and the client can host background threads. A foreground selection check is needed; Gents supplies no automatic discovery for this tool. [Plugin API](https://ampcode.com/docs/plugin-api). |
| Cursor Agent | Hooks expose `conversation_id`/`session_id`, but the documented `sessionStart` runs in the background. A foreground integration must explicitly report current chat IDs; Gents supplies no automatic discovery. [Hooks](https://prod.cursor.com/docs/hooks). |
| Crush | Preliminary tool hooks carry `session_id`, but shared backends can execute other conversations and no foreground selection lifecycle is documented there. Gents supplies no automatic discovery. [Hooks](https://github.com/charmbracelet/crush/blob/main/docs/hooks/README.md). |
| Aider | Its selector is the actual chat history path. Report a confirmed absolute path from your integration, accounting for configuration/CLI overrides; Gents does not guess the default file. [History options](https://aider.chat/docs/config/options.html#history-files). |
| Amazon Q | The builtin cannot resume an explicit identifier; copy rejects this tool even if an integration reports one. [Launch source](https://github.com/aws/amazon-q-developer-cli/blob/main/crates/chat-cli/src/cli/chat/mod.rs). |

## Custom integrations

Send explicit JSON to the helper with the `report` argument:

```json
{ "identifier": "actual-current-id" }
```

To clear it, send `{ "clear": true }`. A delayed clear can include
`"expected": "old-id"`, so it cannot clear a newer conversation. Serialize
reports in foreground lifecycle order; do not send delayed unguarded updates.

The editor-side API is also available:

```lua
require("gents").report_conversation(session_id, "actual-current-id")
require("gents").report_conversation(session_id, nil, "old-id")
```

Here `session_id` is the numeric **Gents terminal ID**, obtained from
`GENTS_SESSION`; the second argument is the CLI's persistent selector. A custom
tool must also supply a `resume` callback that consumes that selector. Unknown,
closed, or exited terminal IDs return false. Retained buffers keep their last
confirmation. See `:help gents.report_conversation()`.
