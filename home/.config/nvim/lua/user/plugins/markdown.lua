return {
	"MeanderingProgrammer/render-markdown.nvim",
	ft = { "markdown" },
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	opts = {},
	keys = {
		{ "<leader>md", "<cmd>RenderMermaid<cr>", ft = "markdown", desc = "Render mermaid diagram (feh)" },
	},
}
