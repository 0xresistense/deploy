-- Enable the native Lua bytecode cache BEFORE anything else (biggest startup win).
vim.loader.enable()

require("user")
