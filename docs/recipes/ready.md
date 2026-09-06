# Agent ready notifications

`AgentsReady` lets your configuration react when an agent finishes a response
or sends a terminal notification. For example:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "AgentsReady",
  callback = function(ev)
    if not ev.data.focused then
      vim.notify(ev.data.label .. " is waiting")
    end
  end,
})
```

The event includes `id`, `label`, `tool`, `buf`, optional `win`, `visible`,
`focused`, and `source` (`"hook"` or `"osc"`). Each event reflects the configured
signal, which may indicate a completed response or a request for attention.

`visible` means the session is shown in the current tab. Sessions shown only
in other tabs are hidden, as they are in picker labels and status snapshots.
`win` identifies a view in the current tab and is absent when hidden;
`focused` means the current window contains the session.

Choose one notification mechanism per tool to avoid duplicate events.
Hooks use the `NVIM` server address inherited from Neovim and the plugin's
`AGENTS_SESSION` ID. Start the CLI through agents.nvim so both are present.
The examples assume a POSIX shell and `nvim` on `PATH`; an absolute path to
the Neovim executable also works. Merge settings with your existing config.

## Tool support

Checked on 2026-09-05. **Live** means the actual CLI completed a response
inside an agents.nvim terminal on Neovim 0.12.4 and its configured signal
produced an `AgentsReady` event. It does not imply that every error,
cancellation, subagent, or UI mode was tested.

| Built-in tool  | Signal                                         | Verification                                                        |
| -------------- | ---------------------------------------------- | ------------------------------------------------------------------- |
| `claude`       | `Stop` hook                                    | Live: 2.1.261, print mode                                           |
| `codex`        | OSC 9, filtered to `agent-turn-complete`       | Live: 0.153.4, TUI                                                  |
| `opencode`     | `session.idle` plugin event                    | Live: 1.18.23, default TUI; broader idle signal                     |
| `opencode2`    | V2 `session.execution.succeeded` event         | Unverified: beta API/dependency mismatch and provider authorization |
| `amp`          | `agent.end`, status `done`                     | Live: 0.0.1785660266-g6a1789, execute mode                          |
| `aider`        | Notification command                           | Broader attention signal; not live-tested                           |
| `copilot`      | `agentStop` hook                               | Documented; not live-tested                                         |
| `crush`        | OSC notifications                              | Broader attention signal; not live-tested                           |
| `cursor-agent` | `afterAgentResponse` hook                      | Documented assistant-message boundary; not live-tested              |
| `gemini`       | `AfterAgent` hook                              | Live: 0.58.0, print mode                                            |
| `grok`         | `Stop` hook                                    | Source-confirmed; not live-tested                                   |
| `pi`           | `agent_settled`, final assistant reason `stop` | Live: 0.85.1, print mode; error case also checked                   |
| `q`            | Agent `stop` hook                              | Documented; not live-tested                                         |
| `qwen`         | `Stop` hook                                    | Live: 0.23.0, print mode                                            |

Claude, Codex, Gemini, Pi, and Qwen used local static responses while their actual
CLIs drove the normal response lifecycle. Amp and OpenCode used a hosted
response. Each successful check produced one event with the correct session
ID: `source = "osc"` for Codex, `"hook"` for the others. Pi's error response
produced no ready event.

## Claude Code

Add a `Stop` command to `.claude/settings.json` (or your user settings):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"$NVIM\" ] && [ -n \"$AGENTS_SESSION\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'agents'.ready($AGENTS_SESSION)\" >/dev/null 2>&1; fi"
          }
        ]
      }
    ]
  }
}
```

`Stop` is the main response hook; `SubagentStop` is separate. It does not
cover user interruption or API failures. See the
[Claude hooks reference](https://code.claude.com/docs/en/hooks#stop).

## Codex

Add to `~/.codex/config.toml`:

```toml
[tui]
notifications = ["agent-turn-complete"]
notification_method = "osc9"
notification_condition = "always"
```

This enables the terminal notification that agents.nvim already receives.
`always` lets your Neovim callback decide whether focus should suppress a
notification. This setting is for the TUI, not `codex exec`. See the
[Codex advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).

## OpenCode

Create `.opencode/plugins/agents-ready.js`:

```js
import { execFileSync } from "node:child_process";

export const AgentsReady = async () => ({
  event: async ({ event }) => {
    const server = process.env.NVIM;
    const id = process.env.AGENTS_SESSION;
    if (event.type !== "session.idle" || !server || !/^\d+$/.test(id ?? "")) return;

    execFileSync(
      "nvim",
      ["--server", server, "--remote-expr", `v:lua.require'agents'.ready(${id})`],
      { stdio: "ignore" },
    );
  },
});
```

Use the default TUI. In 1.18.23, `opencode run` and `run --interactive`
completed a response but did not deliver this callback to the loaded plugin.
`session.idle` can also report cancellation and other idle transitions; this
minimal handler does not filter child sessions. See the
[plugin documentation](https://opencode.ai/docs/plugins/) and
[idle lifecycle implementation](https://github.com/anomalyco/opencode/blob/v1.18.23/packages/opencode/src/session/run-state.ts#L70).

## Amp

Create `.amp/plugins/agents-ready.js`:

```js
import { execFileSync } from "node:child_process";

export default function (amp) {
  amp.on("agent.end", (event) => {
    const server = process.env.NVIM;
    const id = process.env.AGENTS_SESSION;
    if (event.status !== "done" || !server || !/^\d+$/.test(id ?? "")) return;

    execFileSync(
      "nvim",
      ["--server", server, "--remote-expr", `v:lua.require'agents'.ready(${id})`],
      { stdio: "ignore" },
    );
  });
}
```

Execute-mode verification used `--plugin-ready-timeout 10` so the first
turn waited for plugin initialization. See the
[Amp plugin API](https://ampcode.com/docs/plugin-api) and
[plugin loading instructions](https://ampcode.com/docs/customize/plugins).

## Gemini CLI

Save this as an absolute path such as `/path/to/agents-ready.sh`:

```sh
#!/bin/sh
cat >/dev/null
if [ -n "$NVIM" ] && [ -n "$AGENTS_SESSION" ]; then
  nvim --server "$NVIM" --remote-expr "v:lua.require'agents'.ready($AGENTS_SESSION)" >/dev/null 2>&1
fi
printf '{}\n'
```

It consumes the hook input and keeps stdout valid for Gemini's hook protocol.
Add to `.gemini/settings.json`, replacing the script path:

```json
{
  "hooks": {
    "AfterAgent": [
      {
        "hooks": [
          {
            "type": "command",
            "name": "agents-ready",
            "command": "sh /path/to/agents-ready.sh"
          }
        ]
      }
    ]
  }
}
```

See the [Gemini hooks reference](https://geminicli.com/docs/hooks/reference/).

## Pi

Create `.pi/extensions/agents-ready.ts`:

```ts
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";

export default function (pi: ExtensionAPI) {
  let stopReason: string | undefined;

  pi.on("agent_start", () => {
    stopReason = undefined;
  });
  pi.on("message_end", (event) => {
    if (event.message.role === "assistant") stopReason = event.message.stopReason;
  });
  pi.on("agent_settled", () => {
    const server = process.env.NVIM;
    const id = process.env.AGENTS_SESSION;
    if (stopReason !== "stop" || !server || !/^\d+$/.test(id ?? "")) return;

    execFileSync(
      "nvim",
      ["--server", server, "--remote-expr", `v:lua.require'agents'.ready(${id})`],
      { stdio: "ignore" },
    );
  });
}
```

Restart Pi or use `/reload` in a trusted project. You can also load the file
explicitly with `pi -e /absolute/path/agents-ready.ts`, as in the live check.

`agent_settled` follows retries and auto-compaction. The last assistant's
stop reason filters failed or aborted responses. See the
[Pi extension lifecycle](https://github.com/earendil-works/pi/blob/v0.85.1/packages/coding-agent/docs/extensions.md#agent_start--agent_end--agent_settled).

## Qwen Code

Add to `.qwen/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"$NVIM\" ] && [ -n \"$AGENTS_SESSION\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'agents'.ready($AGENTS_SESSION)\" >/dev/null 2>&1; fi"
          }
        ]
      }
    ]
  }
}
```

`StopFailure` is a separate hook for failures. See the
[Qwen hooks guide](https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/).

## Documented integrations awaiting verification

These configurations follow upstream documentation or source, but have not yet
produced `AgentsReady` in a live test here. Merge them into existing configuration.
Use an absolute Neovim executable path if `nvim` is unavailable to hook commands.

### OpenCode 2

**Unverified; no working recipe yet.** V2 has a separate plugin API. Its
`session.execution.succeeded` event is distinct from failed and interrupted
executions; a subscriber must also filter its location and child sessions.
Do not copy the OpenCode 1 plugin into V2. See the
[V2 plugin guide](https://opencode.ai/v2/docs/build/plugins) and
[event API](https://opencode.ai/v2/docs/api).

Testing 0.0.0-beta-19157 with `run --standalone` first failed provider
authorization. A local static-provider attempt then found an unsupported
provider package and an unresolved plugin dependency in the isolated setup.
The installed beta and the current documented configuration did not agree,
so there is no verified snippet to recommend. Future verification should use
`--standalone` so its server inherits the terminal's session environment.

### GitHub Copilot CLI

**Documented; unverified.** Create `.github/hooks/agents-ready.json`, then restart
Copilot. `agentStop` reports the main agent finishing a turn; avoid `sessionEnd`
and background-agent notification events. The hook's `stopReason` is `end_turn`.
[Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference)
and [configuration locations](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks).

```json
{
  "version": 1,
  "hooks": {
    "agentStop": [
      {
        "type": "command",
        "bash": "if [ -n \"${NVIM:-}\" ] && [ -n \"${AGENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'agents'.ready($AGENTS_SESSION)\" >/dev/null; fi",
        "timeoutSec": 5
      }
    ]
  }
}
```

### Grok CLI

**Documented; unverified.** This refers to `superagent-ai/grok-cli`, not other
executables named `grok`. Add the following to `~/.grok/user-settings.json`.
Its `Stop` dispatch is separate from API-error `StopFailure`.
[Lifecycle source](https://github.com/superagent-ai/grok-cli/blob/fb97af83f06dca873281d60168430f06c8de6324/src/agent/agent.ts#L2152).

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"${NVIM:-}\" ] && [ -n \"${AGENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'agents'.ready($AGENTS_SESSION)\" >/dev/null; fi",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

This version only loads hooks from user settings and hardcodes the home-directory
path. Verification was left pending to preserve existing user configuration.
[Hook loader](https://github.com/superagent-ai/grok-cli/blob/fb97af83f06dca873281d60168430f06c8de6324/src/hooks/config.ts#L5)
and [settings path](https://github.com/superagent-ai/grok-cli/blob/fb97af83f06dca873281d60168430f06c8de6324/src/utils/settings.ts#L185).

### Amazon Q CLI

**Documented; unverified.** Add this `hooks` field to the agent JSON you use under
`.amazonq/cli-agents/` or `~/.aws/amazonq/cli-agents/`; select that agent with
`q chat --agent <name>`. The lowercase `stop` hook runs after each assistant
response. This recipe targets the legacy `q` executable.
[Hook reference](https://github.com/aws/amazon-q-developer-cli/blob/15cc8f3cd18c4272925ce1c7053268eedff1ea0a/docs/hooks.md)
and [agent selection](https://github.com/aws/amazon-q-developer-cli/blob/15cc8f3cd18c4272925ce1c7053268eedff1ea0a/docs/default-agent-behavior.md).

```json
{
  "hooks": {
    "stop": [
      {
        "command": "if [ -n \"${NVIM:-}\" ] && [ -n \"${AGENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'agents'.ready($AGENTS_SESSION)\" >/dev/null; fi",
        "timeout_ms": 5000
      }
    ]
  }
}
```

### Cursor Agent

**Documented assistant-response event; unverified.** Add this to
`.cursor/hooks.json`. Cursor's CLI changelog confirms `afterAgentResponse` support;
the event reports a completed assistant message. Whole-turn completion and error
behavior have not been verified here, so do not use it as a strict success flag.
[CLI changelog](https://cursor.com/docs/cli/changelog) and
[hook reference](https://cursor.com/docs/hooks#afteragentresponse).

```json
{
  "version": 1,
  "hooks": {
    "afterAgentResponse": [
      {
        "command": "if [ -n \"${NVIM:-}\" ] && [ -n \"${AGENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'agents'.ready($AGENTS_SESSION)\" >/dev/null; fi"
      }
    ]
  }
}
```

## Broader attention notifications

These options signal when a tool needs attention, including events other than
completed turns. **Live behavior is unverified.**

### Aider

Aider's `notifications-command` runs when input is requested after LLM work starts.
It can also run for confirmation questions or after an error. To opt into that
broader behavior, add this to `.aider.conf.yml`:
[configuration reference](https://aider.chat/docs/config/aider_conf.html),
[notification implementation](https://github.com/Aider-AI/aider/blob/5dc9490bb35f9729ef2c95d00a19ccd30c26339c/aider/io.py#L969).

```yaml
notifications: true
notifications-command: >-
  if [ -n "${NVIM:-}" ] && [ -n "${AGENTS_SESSION:-}" ]; then nvim --server "$NVIM" --remote-expr "v:lua.require'agents'.ready($AGENTS_SESSION)" >/dev/null; fi
```

Aider captures command output, so printing OSC to the hook's stdout is insufficient;
the remote-expression command above communicates through Neovim's socket.

### Crush

Crush can emit OSC notifications with this option in `.crushrc`:

```text
option notifications osc
```

The same stream includes completed turns, permission requests, and questions.
Notifications require terminal focus reporting and are suppressed while focused.
Crush's `PreToolUse` command hook runs before tool calls. Use OSC notifications
for turn completion and requests for attention.
[Notification behavior](https://github.com/charmbracelet/crush/blob/v0.92.0/internal/ui/model/ui.go#L577),
[configuration](https://github.com/charmbracelet/crush#notifications), and
[hook support](https://github.com/charmbracelet/crush/blob/35a7bcab084a6022717d31b110c538a68d6fadf7/docs/hooks/README.md).
