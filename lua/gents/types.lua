---@meta

---Normalize a CLI terminal title; nil means the current conversation is unnamed.
---@alias gents.TitleParser fun(title: string, session: gents.Session): string?

---@class gents.Tool
---@field name string
---@field cmd string[]
---@field env? table<string, string|false>
---@field url? string
---@field location? fun(path: string, range?: gents.Range): string
---@field title? gents.TitleParser|false Uses the terminal title without a parser; false disables reporting.
---@field enabled? boolean

---Tool fields supplied to setup; the table key supplies the name.
---@class gents.ToolOverride
---@field cmd? string[]
---@field env? table<string, string|false>
---@field url? string
---@field location? fun(path: string, range?: gents.Range): string
---@field title? gents.TitleParser|false Uses the terminal title without a parser; false disables reporting.
---@field enabled? boolean

---Evaluated when a float opens and on VimResized.
---@alias gents.FloatValue number|fun(): number

---Partial float defaults. Width/height in (0, 1] are screen proportions; cell sizes round down.
---@class gents.FloatOptions: vim.api.keyset.win_config
---@field width? gents.FloatValue
---@field height? gents.FloatValue
---@field row? gents.FloatValue
---@field col? gents.FloatValue

---An inline float layout, or the complete floating-window defaults after setup.
---@class gents.FloatConfig: gents.FloatOptions
---@field width gents.FloatValue
---@field height gents.FloatValue

---An Ex command that creates a window, "float", "current", inline float options,
---or a callback that creates or chooses a window; the plugin assigns its buffer.
---@alias gents.Layout string|gents.FloatConfig|fun(): integer

---@class gents.NewOptions
---@field cmd? string[] Complete argv override; mutually exclusive with args.
---@field args? string[]
---@field layout? gents.Layout
---@field label? string

---@class gents.ShowOptions
---@field layout? gents.Layout Explicit placement; preserves existing session views.

---@class gents.SendOptions
---@field target? gents.Target
---@field submit? boolean Send Enter after pasting; defaults to false.
---@field focus? boolean Focus the destination and enter terminal input; defaults to true.

---Session picker markers; override either value to use different glyphs or ASCII.
---@class gents.IconsOptions
---@field visible? string
---@field hidden? string

---@class gents.Icons: gents.IconsOptions
---@field visible string
---@field hidden string

---@class gents.SetupOptions
---@field layout? gents.Layout
---@field float? gents.FloatOptions
---@field buflisted? boolean List newly created session buffers in normal buffer lists; defaults to false.
---@field picker? gents.Picker
---@field picker_help? boolean Show binding hints in the built-in Snacks picker; defaults to true.
---@field icons? gents.IconsOptions
---@field on_exit? "keep"|"close"
---@field tools? table<string, gents.ToolOverride|false>
---@field prompts? table<string, gents.Item[]>
---@field keys? gents.Keymap[]

---@class gents.Config
---@field layout gents.Layout
---@field float gents.FloatConfig
---@field buflisted boolean
---@field picker? gents.Picker
---@field picker_help boolean
---@field icons gents.Icons
---@field on_exit "keep"|"close"
---@field tools table<string, gents.Tool>
---@field prompts table<string, gents.Item[]>
---@field keys gents.Keymap[]

---@alias gents.SessionState "starting"|"ready"|"exited"

---@class gents.SessionEvent
---@field id integer
---@field win? integer
---@field exit_code? integer

---@class gents.SendEvent
---@field id integer
---@field submit boolean

---@class gents.TitleEvent
---@field id integer
---@field title? string Absent when the conversation becomes unnamed.

---@class gents.ReadyEvent
---@field id integer
---@field label string
---@field tool string
---@field buf integer
---@field win? integer A window showing the session in the current tab; focused view preferred.
---@field visible boolean Shown in a window in the current tab.
---@field focused boolean
---@field source "osc"|"hook"

---@class gents.Status
---@field id integer
---@field tool string
---@field label string
---@field title? string Conversation title; does not change the targeting label.
---@field visible boolean Shown in a window in the current tab.
---@field state gents.SessionState
---@field cwd string

---Inclusive endpoints: one-based rows and zero-based byte columns.
---@class gents.Range
---@field kind "char"|"line"|"block"
---@field start { [1]: integer, [2]: integer }
---@field finish { [1]: integer, [2]: integer }

---@class gents.Context
---@field win integer
---@field buf integer
---@field cwd string
---@field cursor { [1]: integer, [2]: integer }
---@field range? gents.Range

---@class gents.Provider
---@field desc string
---@field render fun(ctx: gents.Context): gents.Part[]|nil

---@alias gents.Part { text: string }|{ path: string, range?: gents.Range }|{ code: string, ft?: string }
---@alias gents.Item string|gents.Part|{ any: gents.Item[] }|fun(ctx: gents.Context): gents.Part[]|nil
---@alias gents.CommandName "actions"|"close"|"focus"|"hide"|"new"|"pick"|"send"|"toggle"
---@alias gents.KeyAction gents.CommandName
---@alias gents.KeyMode "n"|"i"|"x"|"s"|"v"|"t"

---@class gents.Keymap
---@field [1] string
---@field [2] gents.KeyAction|fun()
---@field mode? gents.KeyMode|gents.KeyMode[]
