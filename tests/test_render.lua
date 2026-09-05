local test = require("mini.test")
local expect = test.expect.equality
local render = require("agents.render")
local tools = require("agents.tools")
local T = test.new_set()

---@type agents.Context
local ctx = { win = 1, buf = 1, cwd = "/workspace", cursor = { 12, 3 } }

---@param first integer
---@param last? integer
---@return agents.Range
local function lines(first, last)
  return { kind = "line", start = { first, 0 }, finish = { last or first, 0 } }
end

T["composition resolves names, literals, fallbacks, and inline providers"] = function()
  local providers = require("agents.providers")
  local original = assert(providers.get("file"))
  test.finally(function()
    providers.register("file", original)
  end)
  providers.register("file", {
    desc = "Test file",
    render = function()
      return { { path = "/workspace/main.lua" } }
    end,
  })
  local unused = false
  ---@type agents.Item[]
  local items = {
    { text = "Explain:" },
    "file",
    {
      any = {
        function()
          return nil
        end,
        {
          any = {
            function()
              return {}
            end,
            { code = "print('hi')", ft = "lua" },
          },
        },
        function()
          unused = true
          return { { text = "unused" } }
        end,
      },
    },
    function(captured)
      return {
        { text = "cwd: " .. captured.cwd },
        { path = "/workspace/other.lua", range = lines(2) },
      }
    end,
  }
  expect(render.resolve(items, ctx), {
    { text = "Explain:" },
    { path = "/workspace/main.lua" },
    { code = "print('hi')", ft = "lua" },
    { text = "cwd: /workspace" },
    { path = "/workspace/other.lua", range = lines(2) },
  })
  expect(unused, false)
end

T["a required missing provider prevents partial output"] = function()
  expect(
    render.resolve({
      { text = "Do not send alone" },
      function()
        return nil
      end,
    }, ctx),
    nil
  )
  expect(
    render.resolve({
      {
        any = {
          function()
            return {}
          end,
          function()
            return nil
          end,
        },
      },
    }, ctx),
    nil
  )
  expect(render.resolve({}, ctx), nil)
end

T["unknown names fail before any provider runs, including unused fallbacks"] = function()
  local called = false
  test.expect.error(function()
    render.resolve({
      function()
        called = true
        return { { text = "first" } }
      end,
      { any = { { text = "available" }, "missing-provider" } },
    }, ctx)
  end, "unknown provider: missing%-provider")
  expect(called, false)
end

T["resolved parts do not retain mutable caller or provider tables"] = function()
  ---@type agents.Part[]
  local supplied = { { text = "initial" }, { path = "/workspace/main.lua", range = lines(2, 5) } }
  local parts = assert(render.resolve({
    function()
      return supplied
    end,
  }, ctx))
  supplied[1] = { text = "changed" }
  assert(supplied[2].range).start[1] = 9
  expect(parts, { { text = "initial" }, { path = "/workspace/main.lua", range = lines(2, 5) } })
end

T["invalid item and provider outputs report clear errors"] = function()
  local invalid = { false, 2, {}, { text = 4 }, { text = "x", code = "y" }, { any = "file" } }
  for _, value in ipairs(invalid) do
    -- Deliberately violate the public item type to exercise runtime validation.
    ---@diagnostic disable-next-line: assign-type-mismatch
    local ok, err = pcall(render.resolve, { value }, ctx)
    expect(ok, false)
    expect(type(err) == "string" and err:find("agents:", 1, true) ~= nil, true)
  end
  local bad_outputs = { "text", { "text" }, { { code = 2 } }, { { path = "" } } }
  for _, output in ipairs(bad_outputs) do
    local ok, err = pcall(render.resolve, {
      function()
        -- Deliberately return malformed provider data.
        ---@diagnostic disable-next-line: return-type-mismatch
        return output
      end,
    }, ctx)
    expect(ok, false)
    expect(type(err) == "string" and err:find("agents:", 1, true) ~= nil, true)
  end
end

T["default locations render rows without columns"] = function()
  expect(render.location("main.lua"), "@main.lua")
  expect(render.location("main.lua", lines(12)), "@main.lua:12")
  expect(render.location("main.lua", lines(12, 15)), "@main.lua:12-15")
  expect(
    render.location("main.lua", { kind = "char", start = { 15, 2 }, finish = { 12, 8 } }),
    "@main.lua:12-15"
  )
end

T["paths use captured cwd and preserve outside paths"] = function()
  expect(
    render.text({
      { path = "/workspace/lua/main.lua" },
      { path = "lua/../main.lua" },
      { path = "../outside.lua" },
      { path = "/workspace-sibling/main.lua" },
      { path = "/workspace" },
      { path = "/workspace/$FILE.lua" },
    }, ctx),
    "@lua/main.lua\n@main.lua\n@/outside.lua\n@/workspace-sibling/main.lua\n@.\n@$FILE.lua"
  )
  local root = vim.deepcopy(ctx)
  root.cwd = "/"
  expect(render.text({ { path = "/main.lua" } }, root), "@main.lua")
  root.cwd = "/workspace/"
  expect(render.text({ { path = "/workspace/main.lua" } }, root), "@main.lua")
end

T["the same parts use default, Claude, Gemini, and Qwen notation"] = function()
  ---@type agents.Part[]
  local parts =
    { { text = "Review" }, { path = "/workspace/a file[1].lua", range = lines(12, 15) } }
  expect(render.text(parts, ctx, tools.defaults.codex), "Review\n@a file[1].lua:12-15")
  expect(render.text(parts, ctx, tools.defaults.claude), "Review\n@a file[1].lua#L12-15")
  expect(render.text(parts, ctx, tools.defaults.gemini), "Review\n@a\\ file\\[1\\].lua:12-15")
  expect(render.text(parts, ctx, tools.defaults.qwen), "Review\n@a\\ file\\[1\\].lua:12-15")
  expect(assert(tools.defaults.claude.location)("file.lua", lines(3)), "@file.lua#L3")
end

T["tool escaping preserves ordinary paths and protects parser punctuation"] = function()
  local gemini = assert(tools.defaults.gemini.location)
  local qwen = assert(tools.defaults.qwen.location)
  for _, writer in ipairs({ gemini, qwen }) do
    expect(writer("lua/foo-bar_é.lua"), "@lua/foo-bar_é.lua")
    expect(writer("a,b (draft);$x'\".lua"), "@a\\,b\\ \\(draft\\)\\;\\$x\\'\\\".lua")
  end
  expect(gemini("a\\b.lua"), "@a\\\\b.lua")
  expect(qwen("a\\b.lua"), "@a\\b.lua")
end

T["custom location writers receive normalized paths and structured ranges"] = function()
  ---@type agents.Tool
  local tool = {
    name = "custom",
    cmd = { "custom" },
    location = function(path, range)
      return path .. " (" .. assert(range).kind .. ")"
    end,
  }
  expect(
    render.text({ { path = "/workspace/main.lua", range = lines(2) } }, ctx, tool),
    "main.lua (line)"
  )
end

T["code fences preserve content including backtick delimiters and trailing lines"] = function()
  expect(render.text({ { code = "print('hi')", ft = "lua" } }, ctx), "```lua\nprint('hi')\n```")
  expect(render.text({ { code = "line\n" } }, ctx), "```\nline\n```")
  expect(render.text({ { code = "line\n\n" } }, ctx), "```\nline\n\n```")
  expect(
    render.text({ { code = "```lua\ncode\n```", ft = "markdown" } }, ctx),
    "````markdown\n```lua\ncode\n```\n````"
  )
  expect(
    render.text({ { text = "first" }, { code = "" }, { text = "last" } }, ctx),
    "first\n```\n\n```\nlast"
  )
end

return T
