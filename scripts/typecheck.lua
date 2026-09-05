local executable = arg[1] or "lua-language-server"
assert(
  vim.fn.executable(executable) == 1,
  "LuaLS not found; install lua-language-server or set LUA_LS"
)

local directory = vim.fn.getcwd() .. "/.test/typecheck"
vim.fn.mkdir(directory, "p")

local config = vim.json.decode(table.concat(vim.fn.readfile(".luarc.json"), "\n"))
config["workspace.library"] = { assert(vim.env.VIMRUNTIME) .. "/lua" }
-- Local editor configuration is not part of the plugin or its test suite.
vim.list_extend(config["workspace.ignoreDir"], { ".nvim.lua" })
local config_path = directory .. "/luarc.json"
vim.fn.writefile({ vim.json.encode(config) }, config_path)

local result = vim
  .system({
    executable,
    "--check=" .. vim.fn.getcwd(),
    "--checklevel=Warning",
    "--check_format=pretty",
    "--configpath=" .. config_path,
    "--logpath=" .. directory .. "/log",
    "--metapath=" .. directory .. "/meta",
  }, { text = true })
  :wait()

io.stdout:write(result.stdout or "")
io.stderr:write(result.stderr or "")
os.exit(result.code)
