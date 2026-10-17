return {
	"stevearc/oil.nvim",
	-- eager so `nvim <dir>` / `vi .` opens oil (directory hijack must be registered at startup)
	lazy = false,
	keys = {
		{ "<C-n>", "<cmd>Oil<cr>", mode = "n", desc = "Open oil file explorer" },
	},
	dependencies = { { "echasnovski/mini.icons", opts = {} } },
	opts = {
		default_file_explorer = true,
		delete_to_trash = false,
		skip_confirm_for_simple_edits = true,
		columns = { "icon", "permissions", "size", "mtime" },
		view_options = { show_hidden = true },
		keymaps = {
			["g?"] = "actions.show_help",
			["F5"] = "actions.refresh",
			["<CR>"] = "actions.select",
			["<C-s>"] = "actions.select_split",
			["<C-v>"] = "actions.select_vsplit",
			["<C-t>"] = "actions.select_tab",
			["-"] = "actions.parent",
			["_"] = "actions.open_cwd",
		},
	},
}
