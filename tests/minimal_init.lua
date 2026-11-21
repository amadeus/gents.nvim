local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

-- Rex integration tests provide their own pane and CLI.
vim.env.REX_SESSION, vim.env.REX_BLOCK = nil, nil
