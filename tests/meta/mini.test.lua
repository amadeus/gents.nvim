---@meta mini.test

-- Types for the mini.test API used by this suite, pinned in Makefile.
-- This is a declaration file only; runtime tests load the real dependency.

---@class MiniTest.Set: table<string, MiniTest.Set|fun(...: any)>

---@class MiniTest.SetOptions
---@field hooks? { pre_case?: fun(), post_case?: fun(), pre_once?: fun(), post_once?: fun() }
---@field parametrize? any[][] Arguments intentionally vary with each test case.

---@class MiniTest.Case
---@field args any[]
---@field desc string[]
---@field test fun(...: any)

---@class MiniTest.Reporter
---@field start fun(cases: MiniTest.Case[])
---@field update fun(case_num: integer)
---@field finish fun()

---@class MiniTest.CollectOptions
---@field emulate_busted? boolean
---@field find_files? fun(): string[]
---@field filter_cases? fun(case: MiniTest.Case): boolean

---@class MiniTest.Config
---@field collect? MiniTest.CollectOptions

---@class MiniTest.Expect
---@field equality fun(left: any, right: any): true
---@field error fun(callback: fun(), pattern?: string): true

---@class MiniTest.Module
---@field setup fun(config?: MiniTest.Config)
---@field new_set fun(opts?: MiniTest.SetOptions, tbl?: MiniTest.Set): MiniTest.Set
---@field finally fun(callback: fun())
---@field collect fun(opts?: MiniTest.CollectOptions): MiniTest.Case[]
---@field execute fun(cases: MiniTest.Case[], opts?: { reporter?: MiniTest.Reporter })
---@field gen_reporter { stdout: fun(opts?: { quit_on_finish?: boolean }): MiniTest.Reporter }
---@field expect MiniTest.Expect

---@type MiniTest.Module
local M
return M
