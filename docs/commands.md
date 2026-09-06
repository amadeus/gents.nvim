# Commands

`:Agents` opens the session picker. Add a command and its arguments to skip
picker choices:

```vim
:Agents actions
:Agents actions hide
:Agents actions hide claude #2
:Agents actions new claude --resume
:Agents actions send file diagnostics --target claude #2
```

The `actions` prefix works with every command below and uses the same handler
as the direct form. For example, `:Agents actions hide` and `:Agents hide` do
the same thing. `actions` cannot select itself.

| Command                                        | Behavior                                                                                                               |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `:Agents new [tool] [args...]`                 | Choose a tool or start the named tool with extra arguments.                                                            |
| `:Agents pick [target]`                        | Choose a session, or show an explicit target.                                                                          |
| `:Agents focus [target]`                       | Focus a session. Without a target, invoking from an agent returns to the previous window and leaves the agent visible. |
| `:Agents toggle [target]`                      | Hide the selected session's views in the current tab, or show it if it is not visible there.                           |
| `:Agents hide [target]`                        | Hide all views of the selected session and keep it running.                                                            |
| `:Agents close [target]`                       | Stop and remove the selected session.                                                                                  |
| `:Agents send [provider...] [--target target]` | Choose context, or send the named providers or prompts.                                                                |

A target is a session ID or its complete label, including spaces. It is
separate from the conversation title displayed in pickers. For `send`, put
providers first and `--target` last: everything after that separator is the
target. `:Agents send --target claude #2` opens the context picker with that
destination already selected.

Session commands choose a target in this order:

1. The explicit ID or label.
2. The session in the current buffer.
3. The only session, counting hidden sessions and sessions in other tabs.
4. The session picker.

Visibility alone does not select a session. From an editor with several
sessions, `toggle` asks which one to show or hide. An unmatched explicit target
reports an error.

Untargeted `pick` always opens the session picker, even from an agent or when
only one session exists. With no sessions, `pick`, `focus`, and `toggle` open
the tool picker; `hide` and `close` do nothing, and `send` reports that a session
must be started first.

Ranges work with `send`, including its composed form:

```vim
:2,5Agents send
:2,5Agents actions send --target claude #2
:2,5Agents actions
```

Without providers, a ranged send sends the selected lines. A range also
survives the actions menu: choosing send uses the captured lines, and choosing
another command reports that only send accepts a range. A visual-mode mapping
calling `require("agents").actions()` preserves the selection as context;
choosing send opens the context picker, and other actions remain available.

Completion follows each choice through `actions`, including tools, session
IDs and labels, providers, prompts, and `--target`. Labels with spaces can be
completed after partially typing them. Extra launch arguments are not
completed by the plugin.

Arguments split on whitespace and are passed literally. Quotes do not group
words, and the plugin does not evaluate Ex commands or shell expansions in
arguments. Use the Lua API for an argument containing spaces:

```lua
require("agents").new("claude", { args = { "--name", "Review this feature" } })
```
