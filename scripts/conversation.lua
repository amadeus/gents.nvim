-- Run with: nvim --headless --clean -u NONE -i NONE -l /path/to/conversation.lua [report|statusline]
-- Stdout stays a neutral hook response, including outside a Gents terminal.
local server = os.getenv("NVIM")
local session_id = os.getenv("GENTS_SESSION")
if server and server ~= "" and session_id and session_id:match("^%d+$") then
  pcall(function()
    local path = assert(debug.getinfo(1, "S")).source:sub(2)
    local root = vim.fs.dirname(vim.fs.dirname(path))
    package.path = root .. "/lua/?.lua;" .. package.path
    local identifier, expected, accepted =
      require("gents.hooks").decode(io.read("*a") or "", arg[1] == "report", arg[1] == "statusline")
    if not accepted then
      return
    end
    local channel = vim.fn.sockconnect("pipe", server, { rpc = true })
    if channel <= 0 then
      return
    end
    -- RPC arguments keep identifiers literal, without shell or Lua interpolation.
    pcall(
      vim.rpcrequest,
      channel,
      "nvim_exec_lua",
      [[
      local id, identifier, expected = ...
      return require("gents").report_conversation(id,
        identifier ~= vim.NIL and identifier or nil,
        expected ~= vim.NIL and expected or nil)
    ]],
      { tonumber(session_id), identifier or vim.NIL, expected or vim.NIL }
    )
    vim.fn.chanclose(channel)
  end)
end
io.stdout:write("{}\n")
