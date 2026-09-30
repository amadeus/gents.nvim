local test = require("mini.test")
local H = require("tests.helpers")
local gents = require("gents")
local references = require("gents.references")
local eq = test.expect.equality
local T = test.new_set({ hooks = { pre_case = H.reset, post_case = H.reset } })

---@param line string
---@param column integer
---@return gents.references.Reference?
local function parse(line, column)
  return references.parse(line, column, require("gents.config").get().tools)
end

---@param line string
---@param needle string
local function cursor_on(line, needle)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, assert(line:find(needle, 1, true)) - 1 })
end

local names = {
  { "claude" },
  { "codex" },
  { "opencode" },
  { "amp" },
  { "aider" },
  { "copilot" },
  { "crush" },
  { "cursor-agent" },
  { "gemini" },
  { "grok" },
  { "omp" },
  { "pi" },
  { "q" },
  { "qwen" },
  { "my-tool" },
  { "my_tool" },
  { "my.tool" },
  { "c++" },
  { "tool[1]" },
  { "my:tool" },
  { "my tool" },
}

T["configured names"] = test.new_set({ parametrize = names }, {
  ---@param name string
  ["match literally in both forms with precise byte bounds"] = function(name)
    require("gents.config").get().tools[name] = { name = name, cmd = { "cat" } }
    for _, token in ipairs({ name .. ":saved.id", name .. ":[saved.id]" }) do
      local prefix = "日本語 `"
      local line = prefix .. token .. "`, next"
      for column = 0, #line do
        local expected = column >= #prefix
            and column < #prefix + #token
            and { tool = name, identifier = "saved.id" }
          or nil
        eq(parse(line, column), expected)
      end
    end
  end,
})

local surroundings = {
  { "`", "`" },
  { '"', '"' },
  { "'", "'" },
  { "(", ")" },
  { "[", "](https://example.com)" },
  { "[resume](", ")" },
  { "<", ">" },
  { "{", "}" },
  { "See ", ", then continue" },
  { "See\t", "; then continue" },
  { "", "!" },
  { "", "?" },
}

T["surroundings"] = test.new_set({ parametrize = surroundings }, {
  ---@param before string
  ---@param after string
  ["keep wrapping punctuation outside a bare reference"] = function(before, after)
    local token = "codex:saved"
    local line = before .. token .. after
    for column = #before, #before + #token - 1 do
      eq(parse(line, column), { tool = "codex", identifier = "saved" })
    end
    eq(parse(line, #before + #token), nil)
  end,
})

local identifiers = {
  { "id.with.dots." },
  { "ses_123-abc" },
  { "T-0123" },
  { "~/history.md" },
  { "./relative/history.md" },
  { "/absolute/history.md" },
  { [[C:\saved\history.md]] },
  { "id:with:colons" },
  { "id=$HOME" },
  { "日本語" },
}

T["bare identifiers"] = test.new_set({ parametrize = identifiers }, {
  ---@param identifier string
  ["retain dots, paths, colons, and literal contents"] = function(identifier)
    eq(parse("codex:" .. identifier, 0), { tool = "codex", identifier = identifier })
  end,
})

local delimited = {
  { "named conversation" },
  { "path with spaces/history.md" },
  { "history (old); 'quoted', file!.md" },
  { "$HOME; $(not-a-command)" },
  { "history[1].md" },
  { " nested [balanced [brackets]] " },
  { "//server/history.md" },
  { [[C:\saved files\history.md]] },
  { "identifier.with.trailing.dot." },
}

T["bracketed identifiers"] = test.new_set({ parametrize = delimited }, {
  ---@param identifier string
  ["preserve literal contents and balanced inner brackets"] = function(identifier)
    local token = "aider:[" .. identifier .. "]"
    local line = "`" .. token .. "`."
    for column = 1, #token do
      eq(parse(line, column), { tool = "aider", identifier = identifier })
    end
    eq(parse(line, 0), nil)
    eq(parse(line, #token + 1), nil)
  end,
})

T["several references select only the one under the cursor"] = function()
  local line = "codex:first, claude:[second codex:literal], opencode:third"
  eq(parse(line, 0), { tool = "codex", identifier = "first" })
  eq(parse(line, assert(line:find("codex:literal", 1, true)) - 1), {
    tool = "claude",
    identifier = "second codex:literal",
  })
  eq(parse(line, assert(line:find("opencode:", 1, true)) - 1), {
    tool = "opencode",
    identifier = "third",
  })
  eq(parse(line, assert(line:find(",", 1, true)) - 1), nil)
end

T["longest literal tool name wins over a shorter prefix"] = function()
  local tools = require("gents.config").get().tools
  tools.my = { name = "my", cmd = { "cat" } }
  tools["my:tool"] = { name = "my:tool", cmd = { "cat" } }
  eq(parse("my:tool:saved", 0), { tool = "my:tool", identifier = "saved" })
end

local ordinary = {
  { "README.md" },
  { "src/codex:saved" },
  { "prefix-codex:saved" },
  { "other.codex:saved" },
  { "codex.lua:12" },
  { "unknown:id" },
  { "unknown:[saved id]" },
  { "unknown:codex:id" },
  { "[codex]:[id]" },
  { "https://example.com/codex:id" },
  { "codex://session" },
  { "https://example.com/?q=codex:id" },
  { "https://example.com/(codex:id)" },
  { "https://example.com/?codex:id" },
  { "mailto:codex:id" },
}

T["ordinary text"] = test.new_set({ parametrize = ordinary }, {
  ---@param line string
  ["falls through at every column without a configured reference"] = function(line)
    for column = 0, #line do
      eq(parse(line, column), nil)
    end
  end,
})

local malformed = {
  { "codex:" },
  { "codex:[]" },
  { "codex:[   ]" },
  { "codex:[missing" },
  { "codex:[unclosed [nested]" },
}

T["malformed references"] = test.new_set({ parametrize = malformed }, {
  ---@param line string
  ["report errors only when the cursor is on the recognized reference"] = function(line)
    for column = 0, #line - 1 do
      test.expect.error(function()
        parse(line, column)
      end, "invalid conversation reference")
    end
    eq(parse(line, #line), nil)
    eq(parse("outside " .. line, 0), nil)
  end,
})

T["an unrelated malformed reference does not block a later valid reference"] = function()
  local line = "codex:[] claude:valid"
  eq(parse(line, assert(line:find("claude:", 1, true)) - 1), {
    tool = "claude",
    identifier = "valid",
  })
end

T["cursor resume launches from the invoking window with literal options"] = function()
  gents.setup({ tools = { codex = { cmd = { "sh", "-c", 'printf "%s\\n" "$@"', "probe" } } } })
  local identifier = "saved; $(not-a-command) $HOME"
  cursor_on("codex:[" .. identifier .. "]", "saved")
  local cwd = vim.fn.getcwd(0)
  local opts = { args = { "extra" }, layout = "current", label = "restored" }
  local original = vim.deepcopy(opts)
  local session = assert(gents.resume_at_cursor(opts))
  H.wait(function()
    return session.state == "exited"
  end)
  eq(session.resume, identifier)
  eq(session.cmd, { "sh", "-c", 'printf "%s\\n" "$@"', "probe", "resume", identifier, "extra" })
  eq(session.cwd, cwd)
  eq(session.label, "restored")
  eq(opts, original)
  local output = table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
  eq(output:find(identifier, 1, true) ~= nil, true)
end

T["cursor resume uses configured adapters even for tools hidden from the picker"] = function()
  gents.setup({
    tools = {
      custom = {
        cmd = { "sh", "-c", 'printf "%s" "$1"', "probe" },
        enabled = false,
        resume = function(id)
          return { id }
        end,
      },
    },
  })
  cursor_on("custom:thread", "custom")
  local session = assert(gents.resume_at_cursor())
  eq(session.tool.name, "custom")
  eq(session.resume, "thread")
end

T["no reference leaves the editor untouched and never opens a tool picker"] = function()
  require("gents.config").get().picker = function()
    error("unexpected picker")
  end
  cursor_on("No conversation here", "conversation")
  local before_bufs, before_wins = vim.api.nvim_list_bufs(), vim.api.nvim_list_wins()
  local cursor = vim.api.nvim_win_get_cursor(0)
  eq(gents.resume_at_cursor(), nil)
  eq(vim.api.nvim_list_bufs(), before_bufs)
  eq(vim.api.nvim_list_wins(), before_wins)
  eq(vim.api.nvim_win_get_cursor(0), cursor)
  eq(gents.sessions(), {})
  gents.setup({ tools = { codex = false } })
  cursor_on("codex:id", "codex")
  eq(gents.resume_at_cursor(), nil)
end

T["malformed, invalid, unsupported, and disabled references do not allocate"] = function()
  gents.setup({ tools = { claude = { resume = false } } })
  local before_bufs, before_wins = vim.api.nvim_list_bufs(), vim.api.nvim_list_wins()
  for _, line in ipairs({
    "codex:",
    "codex:[]",
    "codex:[unterminated",
    "codex:-flag",
    "codex:[id\27]",
    "claude:id",
    "q:id",
  }) do
    cursor_on(line, ":")
    test.expect.error(gents.resume_at_cursor)
    eq(gents.sessions(), {})
    eq(vim.api.nvim_list_bufs(), before_bufs)
    eq(vim.api.nvim_list_wins(), before_wins)
  end
end

T["cursor resume rejects supplied commands and selectors before allocating"] = function()
  cursor_on("codex:from-cursor", "codex")
  for _, name in ipairs({ "cmd", "resume" }) do
    ---@type gents.ResumeAtCursorOptions
    local opts = {}
    rawset(opts, name, name == "cmd" and { "cat" } or "other-id")
    test.expect.error(
      function()
        gents.resume_at_cursor(opts)
      end,
      name == "cmd" and "does not accept a cmd override" or "uses the identifier under the cursor"
    )
    eq(gents.sessions(), {})
  end
end

T["missing executables and failed job starts leave no unintended session"] = function()
  local source = vim.api.nvim_get_current_buf()
  gents.setup({ tools = { codex = { cmd = { "/__gents_missing_executable__" } } } })
  cursor_on("codex:id", "codex")
  test.expect.error(gents.resume_at_cursor)
  eq(gents.sessions(), {})
  H.wait(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if buf ~= source and vim.api.nvim_buf_is_valid(buf) then
        return false
      end
    end
    return true
  end)
end

T["Aider references resolve history paths from the invoking window's cwd"] = function()
  local directory = vim.fn.tempname()
  vim.fn.mkdir(directory, "p")
  directory = assert(vim.uv.fs_realpath(directory))
  local filename = "saved [old] history.md"
  vim.fn.writefile({ "history" }, directory .. "/" .. filename)
  test.finally(function()
    vim.fn.delete(directory, "rf")
  end)
  gents.setup({ tools = { aider = { cmd = { "sh", "-c", 'printf "%s" "$@"', "probe" } } } })
  vim.cmd.lcd(directory)
  cursor_on("aider:[" .. filename .. "]", "history")
  local session = assert(gents.resume_at_cursor({ layout = "float" }))
  eq(session.resume, filename)
  eq(session.cwd, directory)
  eq(session.cmd[6], directory .. "/" .. filename)
end

T["a reference in an agent terminal's output can launch another session"] = function()
  local source = H.new({ cmd = { "printf", "%s", "codex:saved" }, layout = "current" })
  H.wait(function()
    return source.state == "exited"
  end)
  gents.setup({ tools = { codex = { cmd = { "sh", "-c", 'printf "%s" "$@"', "probe" } } } })
  vim.cmd.stopinsert()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local session = assert(gents.resume_at_cursor({ layout = "split" }))
  eq(session.resume, "saved")
  eq(session.id ~= source.id, true)
  eq(gents.sessions(), { source, session })
end

return T
