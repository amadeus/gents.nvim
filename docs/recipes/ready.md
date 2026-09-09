# Agent ready notifications

Ready notifications let you keep editing while a CLI works and return when it
needs your attention. gents.nvim emits a `GentsReady` event when the CLI
sends a supported terminal notification or a hook calls `gents.ready(id)`.
Your Neovim configuration decides how to present that event: a popup, a sound,
or a statusline update.

Depending on the CLI, a notification can mean a response finished or it needs
your input, such as permission to run a command.

## Show a notification in Neovim

Notify when a session needs attention and is not visible in your current tab:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "GentsReady",
  callback = function(ev)
    if not ev.data.visible then
      vim.notify(ev.data.label .. " is waiting")
    end
  end,
})
```

Sessions shown only in another tab count as hidden. See `:help GentsReady`
in the [help reference](../../doc/gents.txt) for the full event details.

## CLI setup

Some CLIs, including Codex, can notify gents.nvim without any additional CLI
configuration. Start with the Neovim callback above. If it already receives
notifications, no further setup is needed.

If it does not, or you want to change when it notifies, use the recipes below.
Some adjust built-in terminal notifications; others add a hook that tells
Neovim when the CLI needs attention.

| Tool                                      | Example setup                  | When it notifies                                                   |
| ----------------------------------------- | ------------------------------ | ------------------------------------------------------------------ |
| [Codex](#codex)                           | Optional notification settings | Completed turns with the filter shown below                        |
| [Claude Code](#claude-code)               | `Stop` hook                    | Main response finished                                             |
| [OpenCode](#opencode)                     | `session.idle` handler         | Session became idle, including cancellation                        |
| [OpenCode 2](#opencode-2)                 | CLI plugin                     | Turn succeeded in the current conversation or an open OpenCode tab |
| [Amp](#amp)                               | `agent.end` handler            | Turn finished without error or cancellation                        |
| [Gemini CLI](#gemini-cli)                 | `AfterAgent` hook              | Final response generated                                           |
| [Pi](#pi)                                 | Extension                      | Automatic work settled after a completed response                  |
| [Qwen Code](#qwen-code)                   | `Stop` hook                    | Main response finished                                             |
| [GitHub Copilot CLI](#github-copilot-cli) | `agentStop` hook               | Main agent finished a turn                                         |
| [Grok CLI](#grok-cli)                     | `Stop` hook                    | Response finished                                                  |
| [Amazon Q CLI](#amazon-q-cli)             | `stop` hook                    | Assistant response finished                                        |
| [Cursor Agent](#cursor-agent)             | `afterAgentResponse` hook      | Assistant message finished                                         |
| [Aider](#aider)                           | Notification command           | Input requested after work starts                                  |
| [Crush](#crush)                           | Enable terminal notifications  | Turn finished or attention needed                                  |

## Codex

Codex's interactive CLI enables terminal notifications by default, so no hook
is needed. By default, it notifies only when it considers the terminal
unfocused and chooses the notification method automatically. If those
notifications already reach your Neovim callback, you can leave your Codex
configuration as it is.

### Optional settings

To receive only completed-turn notifications and let your Neovim callback
decide whether to show them, merge these settings into `~/.codex/config.toml`:

```toml
[tui]
# Notify only when a turn finishes.
notifications = ["agent-turn-complete"]
# Use a terminal notification format that gents.nvim receives.
notification_method = "osc9"
# Let the Neovim callback handle the visibility check.
notification_condition = "always"
```

Codex's automatic method can fall back to a terminal bell, which does not
trigger `GentsReady`. Setting `notification_method = "osc9"` makes the
notification format explicit. These settings apply to the interactive CLI.
See the [Codex defaults](https://learn.chatgpt.com/docs/config-file/config-sample)
and [notification settings](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications).

## Using a hook recipe

Use a hook if your CLI does not send supported terminal notifications, or you
want to notify on a specific event. A hook runs a command that calls
`gents.ready(id)` in Neovim. Avoid adding one for an event you already receive
through terminal notifications, or you may get duplicate notifications.

Start the CLI through gents.nvim so the hook can identify its session. The
examples use the `NVIM` server address and `GENTS_SESSION` ID provided to that
process; you do not need to set them yourself. Shell examples assume a POSIX
shell and `nvim` on `PATH`. Merge the hook settings with your existing CLI
configuration; gents.nvim does not install them for you.

## Claude Code

Use Claude's `Stop` hook to notify when the main agent finishes responding.
Subagents use a separate `SubagentStop` hook; user interruptions and API failures
do not trigger this recipe. Add a `Stop` command to `.claude/settings.json`
(or your user settings):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"$NVIM\" ] && [ -n \"$GENTS_SESSION\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'gents'.ready($GENTS_SESSION)\" >/dev/null 2>&1; fi"
          }
        ]
      }
    ]
  }
}
```

See the
[Claude hooks reference](https://code.claude.com/docs/en/hooks#stop).

## OpenCode

OpenCode's `session.idle` event lets you know the session has stopped working.
It can also fire after cancellation or another idle transition, and this
handler does not filter child sessions. Use this recipe with OpenCode 1;
for OpenCode 2, use the [CLI plugin below](#opencode-2).

Create `.opencode/plugins/gents-ready.js`:

```js
import { execFileSync } from "node:child_process";

export const GentsReady = async () => ({
  event: async ({ event }) => {
    const server = process.env.NVIM;
    const id = process.env.GENTS_SESSION;
    if (event.type !== "session.idle" || !server || !/^\d+$/.test(id ?? "")) return;

    execFileSync(
      "nvim",
      ["--server", server, "--remote-expr", `v:lua.require'gents'.ready(${id})`],
      { stdio: "ignore" },
    );
  },
});
```

See the
[plugin documentation](https://opencode.ai/docs/plugins/) and
[idle lifecycle implementation](https://github.com/anomalyco/opencode/blob/v1.18.23/packages/opencode/src/session/run-state.ts#L70).

## OpenCode 2

This CLI plugin tells gents.nvim when a turn succeeds in the conversation
displayed in OpenCode, or in one of its open tabs. It ignores conversations that
are not open in that CLI, and does not notify for cancellation or errors. Your
`GentsReady` callback above decides whether to show a notification based on the
visibility of the Neovim terminal buffer.

Create `~/.config/opencode/cli-plugins/gents-ready/tui.js`:

```js
import { execFile } from "node:child_process";

export default {
  id: "gents-ready.cli",
  setup(context) {
    const server = process.env.NVIM;
    const id = process.env.GENTS_SESSION;
    if (!server || !/^\d+$/.test(id ?? "")) return;

    return context.data.on("session.execution.succeeded", (event) => {
      const sessionID = event.data.sessionID;
      const current = context.ui.router.current();
      const visible = current.type === "session" && current.sessionID === sessionID;
      const openTab =
        context.ui.tabs.enabled() &&
        context.ui.tabs.list().some((tab) => tab.sessionID === sessionID);
      if (!visible && !openTab) return;

      execFile(
        "nvim",
        ["--server", server, "--remote-expr", `v:lua.require'gents'.ready(${id})`],
        { timeout: 2000 },
        () => {}, // The Neovim session may have closed while OpenCode was working.
      );
    });
  },
};
```

Add the plugin to `~/.config/opencode/cli.json`, keeping any existing entries:

```json
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "plugins": ["./cli-plugins/gents-ready"]
}
```

If you set `XDG_CONFIG_HOME`, use `$XDG_CONFIG_HOME/opencode/` instead of
`~/.config/opencode/` for both files. The plugin path is relative to `cli.json`.
No package installation is needed for this example.

Load this through `cli.json` so it runs in the CLI process, which inherits
`NVIM` and `GENTS_SESSION` from gents.nvim. A plugin loaded in OpenCode's shared
server cannot reliably identify the Neovim terminal that started the CLI.
Start a new `opencode2` session through gents.nvim after adding the files.

See OpenCode 2's [CLI plugin setup](https://opencode.ai/v2/docs/cli/plugins/)
and [CLI plugin API](https://opencode.ai/v2/docs/build/plugins/cli/).

## Amp

Amp reports the outcome of each turn through `agent.end`. This handler notifies
only for status `done`, excluding errors and cancellation. It does not filter
side threads hosted by the same client. Create `.amp/plugins/gents-ready.js`:

```js
import { execFileSync } from "node:child_process";

export default function (amp) {
  amp.on("agent.end", (event) => {
    const server = process.env.NVIM;
    const id = process.env.GENTS_SESSION;
    if (event.status !== "done" || !server || !/^\d+$/.test(id ?? "")) return;

    execFileSync(
      "nvim",
      ["--server", server, "--remote-expr", `v:lua.require'gents'.ready(${id})`],
      { stdio: "ignore" },
    );
  });
}
```

In execute mode, use `--plugin-ready-timeout 10` to let the first turn wait
for plugin initialization. See
[execute mode](https://ampcode.com/docs/cli/execute-mode), the
[Amp plugin API](https://ampcode.com/docs/plugin-api) and
[plugin loading instructions](https://ampcode.com/docs/customize/plugins).

## Gemini CLI

Gemini's `AfterAgent` hook runs after it generates a final response. This recipe
notifies Neovim while returning an empty JSON object to leave the response alone.
Save this as an absolute path such as `/path/to/gents-ready.sh`:

```sh
#!/bin/sh
cat >/dev/null
if [ -n "$NVIM" ] && [ -n "$GENTS_SESSION" ]; then
  nvim --server "$NVIM" --remote-expr "v:lua.require'gents'.ready($GENTS_SESSION)" >/dev/null 2>&1
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
            "name": "gents-ready",
            "command": "sh /path/to/gents-ready.sh"
          }
        ]
      }
    ]
  }
}
```

See the [Gemini hooks reference](https://geminicli.com/docs/hooks/reference/).

## Pi

Pi can continue automatically after a model run through retries, compaction,
or queued follow-ups. `agent_settled` waits until that work settles; checking the
last assistant's stop reason excludes failed or aborted responses. Create
`.pi/extensions/gents-ready.ts`:

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
    const id = process.env.GENTS_SESSION;
    if (stopReason !== "stop" || !server || !/^\d+$/.test(id ?? "")) return;

    execFileSync(
      "nvim",
      ["--server", server, "--remote-expr", `v:lua.require'gents'.ready(${id})`],
      { stdio: "ignore" },
    );
  });
}
```

Restart Pi or use `/reload` in a trusted project. You can also load the file
explicitly with `pi -e /absolute/path/gents-ready.ts`.

See the
[Pi extension lifecycle](https://github.com/earendil-works/pi/blob/v0.85.1/packages/coding-agent/docs/extensions.md#agent_start--agent_end--agent_settled).

## Qwen Code

Qwen's `Stop` hook notifies after the main response finishes. Failures use the
separate `StopFailure` hook. Add to `.qwen/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"$NVIM\" ] && [ -n \"$GENTS_SESSION\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'gents'.ready($GENTS_SESSION)\" >/dev/null 2>&1; fi"
          }
        ]
      }
    ]
  }
}
```

See the
[Qwen hooks guide](https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/).

## GitHub Copilot CLI

`agentStop` reports the main agent finishing a turn with `stopReason: "end_turn"`.
Use it to notify after a response; `sessionEnd` reports the session closing.
Create `.github/hooks/gents-ready.json`, then restart Copilot. See the
[Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference)
and [configuration locations](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks).

```json
{
  "version": 1,
  "hooks": {
    "agentStop": [
      {
        "type": "command",
        "bash": "if [ -n \"${NVIM:-}\" ] && [ -n \"${GENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'gents'.ready($GENTS_SESSION)\" >/dev/null; fi",
        "timeoutSec": 5
      }
    ]
  }
}
```

## Grok CLI

The built-in `grok` tool targets `superagent-ai/grok-cli`. Its `Stop` hook reports
the agent finishing a response; API errors use `StopFailure`. Add the following
to `~/.grok/user-settings.json`, as described in its
[hook configuration](https://github.com/superagent-ai/grok-cli#hooks).

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"${NVIM:-}\" ] && [ -n \"${GENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'gents'.ready($GENTS_SESSION)\" >/dev/null; fi",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Amazon Q CLI

Amazon Q's lowercase `stop` hook runs after each assistant response. This recipe
targets the legacy `q` executable. Add this `hooks` field to the agent JSON you
use under `.amazonq/cli-agents/` or `~/.aws/amazonq/cli-agents/`, and select that
agent with `q chat --agent <name>`. See the
[Hook reference](https://github.com/aws/amazon-q-developer-cli/blob/15cc8f3cd18c4272925ce1c7053268eedff1ea0a/docs/hooks.md)
and [agent selection](https://github.com/aws/amazon-q-developer-cli/blob/main/docs/default-agent-behavior.md).

```json
{
  "hooks": {
    "stop": [
      {
        "command": "if [ -n \"${NVIM:-}\" ] && [ -n \"${GENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'gents'.ready($GENTS_SESSION)\" >/dev/null; fi",
        "timeout_ms": 5000
      }
    ]
  }
}
```

## Cursor Agent

Cursor's `afterAgentResponse` reports a completed assistant message. Use it to
notice new output, rather than as a strict whole-turn success signal. Add this
to `.cursor/hooks.json`. See the
[CLI changelog](https://cursor.com/docs/cli/changelog) and
[hook reference](https://cursor.com/docs/hooks#afteragentresponse).

```json
{
  "version": 1,
  "hooks": {
    "afterAgentResponse": [
      {
        "command": "if [ -n \"${NVIM:-}\" ] && [ -n \"${GENTS_SESSION:-}\" ]; then nvim --server \"$NVIM\" --remote-expr \"v:lua.require'gents'.ready($GENTS_SESSION)\" >/dev/null; fi"
      }
    ]
  }
}
```

## Broader attention notifications

These options are useful when you want to return for questions and permission
requests as well as completed responses.

### Aider

Aider's `notifications-command` runs when input is requested after LLM work starts.
It can also run for confirmation questions or after an error. To opt into that
broader behavior, add this to `.aider.conf.yml`:
[configuration reference](https://aider.chat/docs/config/aider_conf.html),
[notification implementation](https://github.com/Aider-AI/aider/blob/5dc9490bb35f9729ef2c95d00a19ccd30c26339c/aider/io.py#L969).

```yaml
notifications: true
notifications-command: >-
  if [ -n "${NVIM:-}" ] && [ -n "${GENTS_SESSION:-}" ]; then nvim --server "$NVIM" --remote-expr "v:lua.require'gents'.ready($GENTS_SESSION)" >/dev/null; fi
```

Aider captures command output, so printing OSC to the hook's stdout is insufficient;
the remote-expression command above communicates through Neovim's socket.

### Crush

Crush can send terminal notifications after a turn and when it needs attention,
such as a permission decision. Enable OSC notifications in `.crushrc`:

```text
option notifications osc
```

Notifications require terminal focus reporting and are suppressed while focused.
See [desktop notifications](https://github.com/charmbracelet/crush#desktop-notifications)
and [configuration](https://github.com/charmbracelet/crush#configuration).
