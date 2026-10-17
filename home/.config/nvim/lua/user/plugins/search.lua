return {
	"ibhagwan/fzf-lua",
	cmd = "FzfLua",
	keys = {
		{ "<leader>pf", "<cmd>FzfLua files<cr>", desc = "Find files" },
		{ "<C-p>", "<cmd>FzfLua git_files<cr>", desc = "Git files" },
		{ "<leader>ps", "<cmd>FzfLua live_grep<cr>", desc = "Live grep" },
		{ "<leader>vh", "<cmd>FzfLua helptags<cr>", desc = "Help tags" },
	},
	opts = {
		winopts = { height = 0.85, width = 0.85 },
	},
}
