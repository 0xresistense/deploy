-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	vim.fn.system({
		"git", "clone", "--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = { { import = "user.plugins" } },
	defaults = { lazy = true }, -- everything lazy unless the spec says otherwise
	install = { colorscheme = { "carbonfox", "habamax" } },
	checker = { enabled = false }, -- no background update checks
	change_detection = { notify = false },
	rocks = { enabled = false }, -- no plugin here needs luarocks; silences the hererocks healthcheck
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip", "zip", "zipPlugin", "tar", "tarPlugin",
				"tohtml", "2html_plugin", "tutor",
				"netrwPlugin", "rplugin", "spellfile_plugin", "matchit",
				-- KEEP: matchparen (bracket match), shada (persistent marks/registers)
			},
		},
	},
})
