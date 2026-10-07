local test = require("mini.test")
local protocol = require("gents.status_protocol")
local eq = test.expect.equality
local T = test.new_set()

---@param body string
---@return gents.ProgramReport?
local function parse(body)
  return protocol.parse("\027]7501;" .. body)
end

T["pairs, replacement fields, and optional values follow the protocol"] = function()
  eq(
    parse(
      "state=working:badpair:=x:unknown=ignored:state = blocked :kind=auth:progress=0:app=a+._-:id=worker/1:msg=aGk:title="
    ),
    {
      id = "worker/1",
      state = "blocked",
      kind = "auth",
      progress = 0,
      app = "a+._-",
      msg = "hi",
      title = "",
    }
  )
  eq(parse("state=done:kind=question:progress=10:app=a/b"), { id = "", state = "done" })
  eq(parse("state=working:kind=bad:progress=1.5"), { id = "", state = "working" })
  eq(parse("state=blocked:kind=other:progress=101"), { id = "", state = "blocked" })
  eq(parse("state=blocked:progress=-1"), { id = "", state = "blocked" })
  eq(parse("state=future"), nil)
  eq(parse("msg=aGk="), nil)
  eq(parse("state=working:msg=bad;value"), { id = "", state = "working" })
end

T["invalid ids never address the root"] = function()
  for _, id in ipairs({
    "",
    "/a",
    "a/",
    "a//b",
    "a,b",
    "bad*id",
    string.rep("a", 33),
    "a/b/c/d/e/f/g/h/i",
    string.rep("a/", 4) .. string.rep("b", 121),
  }) do
    eq(parse("state=done:id=" .. id), nil)
  end
  local id = table.concat(
    { string.rep("a", 32), string.rep("b", 32), string.rep("c", 32), string.rep("d", 29) },
    "/"
  )
  eq(#id, 128)
  eq(assert(parse("state=working:id=" .. id)).id, id)
end

T["all text is validated before applying the last repeated key"] = function()
  for _, text in ipairs({
    "\0",
    "\n",
    "\127",
    "\194\128",
    "\194\159",
    "\255",
    "\192\128",
    "\237\160\128",
    "\244\144\128\128",
    "\226\130",
  }) do
    eq(parse("state=done:msg=" .. vim.base64.encode(text) .. ":msg=b2s="), nil)
    eq(parse("state=done:title=" .. vim.base64.encode(text)), nil)
  end
  for _, encoded in ipairs({ "a", "a===", "aGk==", "aG_k", "aG.k" }) do
    eq(parse("state=done:msg=" .. encoded), nil)
  end
  local text = "日本語 café 😀"
  eq(assert(parse("state=done:msg=" .. vim.base64.encode(text))).msg, text)
  eq(parse("state=done:msg=:title="), { id = "", state = "done", msg = "", title = "" })
end

T["hard caps discard the entire report including overridden fields"] = function()
  eq(
    parse("state=done:msg=" .. vim.base64.encode(string.rep("a", 2048))),
    { id = "", state = "done", msg = string.rep("a", 2048) }
  )
  eq(parse("state=done:msg=" .. vim.base64.encode(string.rep("a", 2049)) .. ":msg="), nil)
  eq(parse("state=done:title=" .. vim.base64.encode(string.rep("a", 193)) .. ":title="), nil)
  eq(parse("state=done:app=" .. string.rep("a", 33) .. ":app=ok"), nil)
  eq(parse("state=done:" .. string.rep("x", 17) .. "=ignored"), nil)
  eq(parse("state=done:unknown=" .. string.rep("a", 4096)), nil)
end

T["whole-sequence cap includes the received terminator"] = function()
  local sequence = "\027]7501;state=done:unknown="
  sequence = sequence .. string.rep("a", 4095 - #sequence)
  eq(assert(protocol.parse(sequence, "\007")).state, "done")
  eq(protocol.parse(sequence, "\027\\"), nil)
end

return T
