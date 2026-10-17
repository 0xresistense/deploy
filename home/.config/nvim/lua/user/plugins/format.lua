return {
	"stevearc/conform.nvim",
	keys = {
		{
			"<leader>f",
			function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
			mode = { "n", "v" },
			desc = "Format code",
		},
	},
	cmd = { "ConformInfo" },
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			rust = { "rustfmt" },
			python = { "black" },
			javascript = { "prettier" },
			typescript = { "prettier" },
			javascriptreact = { "prettier" },
			typescriptreact = { "prettier" },
			html = { "prettier" },
			c = { "clang_format" },
			cpp = { "clang_format" },
			json = { "prettier" },
			markdown = { "prettier" },
			sh = { "shfmt" },
			css = { "prettier" },
		},
		formatters = {
			prettier = {
				prepend_args = {
					"--print-width", "92",
					"--trailing-comma", "es5",
					"--no-semi",
					"--bracket-spacing",
					"--arrow-parens", "always",
				},
			},
			stylua = {
				prepend_args = { "--search-parent-directories" },
			},
		},
		notify_on_error = true,
	},
}
