return {
	"nvim-treesitter/nvim-treesitter",
	-- master is archived and its injection queries crash 0.12's runtime (get_range on
	-- a nil node — see docs/specs). main was ALSO archived by the maintainer on
	-- 2026-04-03 (maintainer burnout / 0.11-compat dispute): still works as pinned,
	-- but frozen — no further parser/query updates. Neovim 0.12 core bundles common
	-- parsers natively now; this plugin's remaining job is the abstraction layer +
	-- parsers not yet bundled (js/ts/rust/go/etc).
	branch = "main",
	build = ":TSUpdate",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		require("nvim-treesitter").setup({
			install_dir = vim.fn.stdpath("data") .. "/site",
		})

		local ensure = {
			"c", "cpp", "rust", "go", "lua", "vim", "vimdoc", "query",
			"javascript", "typescript", "tsx", "python",
			"bash", "json", "markdown", "markdown_inline", "asm",
		}
		-- install missing parsers (async; no-op if already present)
		pcall(function()
			require("nvim-treesitter").install(ensure)
		end)

		-- main-branch model: highlighting is provided by Neovim; enable it per-buffer.
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("user.treesitter", {}),
			callback = function(ev)
				if vim.b[ev.buf].bigfile then return end
				pcall(vim.treesitter.start, ev.buf)
			end,
		})
	end,
}
