---@meta

---Normalize a CLI terminal title; nil means the current conversation is unnamed.
---@alias agents.TitleParser fun(title: string, session: agents.Session): string?

---@class agents.Tool
---@field name string
---@field cmd string[]
---@field env? table<string, string|false>
---@field url? string
---@field location? fun(path: string, range?: agents.Range): string
---@field title? agents.TitleParser|false Uses the terminal title without a parser; false disables reporting.
---@field enabled? boolean

---Tool fields supplied to setup; the table key supplies the name.
---@class agents.ToolOverride
---@field cmd? string[]
---@field env? table<string, string|false>
---@field url? string
---@field location? fun(path: string, range?: agents.Range): string
---@field title? agents.TitleParser|false Uses the terminal title without a parser; false disables reporting.
---@field enabled? boolean

---Partial defaults for floating windows. Fractions in (0, 1] are screen proportions.
---@class agents.FloatOptions: vim.api.keyset.win_config
---@field width? number
---@field height? number

---An inline float layout, or the complete floating-window defaults after setup.
---@class agents.FloatConfig: agents.FloatOptions
---@field width number
---@field height number

---An Ex command that creates a window, "float", "current", inline float options,
---or a callback that returns the window in which to display the buffer.
---@alias agents.Layout string|agents.FloatConfig|fun(buf: integer): integer

---@class agents.NewOptions
---@field cmd? string[] Complete argv override; mutually exclusive with args.
---@field args? string[]
---@field layout? agents.Layout
---@field label? string

---@class agents.ShowOptions
---@field layout? agents.Layout

---@class agents.SendOptions
---@field target? agents.Target
---@field submit? boolean Send Enter after pasting; defaults to false.
---@field focus? boolean Focus the destination; defaults to false.

---@class agents.SetupOptions
---@field layout? agents.Layout
---@field float? agents.FloatOptions
---@field picker? agents.Picker
---@field on_exit? "keep"|"close"
---@field tools? table<string, agents.ToolOverride|false>
---@field prompts? table<string, agents.Item[]>
---@field keys? agents.Keymap[]

---@class agents.Config
---@field layout agents.Layout
---@field float agents.FloatConfig
---@field picker? agents.Picker
---@field on_exit "keep"|"close"
---@field tools table<string, agents.Tool>
---@field prompts table<string, agents.Item[]>
---@field keys agents.Keymap[]

---@alias agents.SessionState "starting"|"ready"|"exited"

---@class agents.SessionEvent
---@field id integer
---@field win? integer
---@field exit_code? integer

---@class agents.SendEvent
---@field id integer
---@field submit boolean

---@class agents.TitleEvent
---@field id integer
---@field title? string Absent when the conversation becomes unnamed.

---@class agents.ReadyEvent
---@field id integer
---@field label string
---@field tool string
---@field buf integer
---@field win? integer
---@field visible boolean
---@field focused boolean
---@field source "osc"|"hook"

---@class agents.Status
---@field id integer
---@field tool string
---@field label string
---@field title? string Conversation title; does not change the targeting label.
---@field visible boolean
---@field state agents.SessionState
---@field cwd string

---Inclusive endpoints: one-based rows and zero-based byte columns.
---@class agents.Range
---@field kind "char"|"line"|"block"
---@field start { [1]: integer, [2]: integer }
---@field finish { [1]: integer, [2]: integer }

---@class agents.Context
---@field win integer
---@field buf integer
---@field cwd string
---@field cursor { [1]: integer, [2]: integer }
---@field range? agents.Range

---@class agents.Provider
---@field desc string
---@field render fun(ctx: agents.Context): agents.Part[]|nil

---@alias agents.Part { text: string }|{ path: string, range?: agents.Range }|{ code: string, ft?: string }
---@alias agents.Item string|agents.Part|{ any: agents.Item[] }|fun(ctx: agents.Context): agents.Part[]|nil
---@alias agents.CommandName "actions"|"close"|"focus"|"hide"|"new"|"pick"|"send"|"toggle"
---@alias agents.KeyAction agents.CommandName
---@alias agents.KeyMode "n"|"x"|"t"

---@class agents.Keymap
---@field [1] string
---@field [2] agents.KeyAction|fun()
---@field mode? agents.KeyMode|agents.KeyMode[]
