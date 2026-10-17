-- Core (pure-vim, no plugin requires) loads synchronously and instantly.
require("user.core.options")
require("user.core.keymaps")
require("user.core.autocmds")
require("user.core.commands")
require("user.core.runner")

-- Plugin manager + specs (everything below is lazy-loaded).
require("user.core.lazy")
