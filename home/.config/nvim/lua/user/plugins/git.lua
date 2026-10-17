return {
	{
		"tpope/vim-fugitive",
		-- VeryLazy so FugitiveHead() exists for the statusline branch indicator (post-UI, non-blocking).
		event = "VeryLazy",
		cmd = { "Git", "G", "Gdiffsplit", "Gread", "Gwrite", "Gblame" },
		keys = {
			{ "<leader>gs", vim.cmd.Git, desc = "Git status" },
		},
		init = function()
			vim.api.nvim_create_autocmd("BufWinEnter", {
				group = vim.api.nvim_create_augroup("user.fugitive", {}),
				-- "fugitive://*" matches only fugitive buffers — avoids firing on
				-- every window enter just to bail on the ft check.
				pattern = "fugitive://*",
				callback = function()
					local opts = { buffer = vim.api.nvim_get_current_buf(), remap = false }
					vim.keymap.set("n", "<leader>p", function() vim.cmd.Git("push") end, opts)
					vim.keymap.set("n", "<leader>P", function() vim.cmd.Git({ "pull", "--rebase" }) end, opts)
					vim.keymap.set("n", "<leader>t", ":Git push -u origin ", opts)
				end,
			})
		end,
	},

	-- Inline hunk signs/blame/stage — complements fugitive (which is command/porcelain-only).
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			-- Skip the bigfile guard's buffers: hunk diffing a huge file is its own perf cost.
			on_attach = function(bufnr)
				if vim.b[bufnr].bigfile then return false end
				local gs = require("gitsigns")
				local function bmap(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
				end
				bmap("n", "]c", gs.next_hunk, "Next hunk")
				bmap("n", "[c", gs.prev_hunk, "Prev hunk")
				bmap("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
				bmap("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
				bmap("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
				bmap("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line")
			end,
		},
	},
}
