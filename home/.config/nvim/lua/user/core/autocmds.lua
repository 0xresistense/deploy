local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Bigfile guard. Registered here (core, loaded before core.lazy) so it wins
-- the race against treesitter/nvim-lspconfig's own BufReadPre lazy-load
-- triggers: vim.b[buf].bigfile is already set by the time their FileType /
-- LspAttach callbacks run. Threshold matches LazyVim's default (1.5MB) —
-- past this, unconditional treesitter parse + LSP full-doc sync turns a
-- sub-second file open into multi-second hangs (measured on a 22MB/400k-line
-- file: 0.19s with neither vs 2.9s with both).
local BIGFILE_THRESHOLD = 1.5 * 1024 * 1024
autocmd("BufReadPre", {
	group = augroup("user.bigfile", {}),
	pattern = "*",
	callback = function(ev)
		local stat = vim.uv.fs_stat(ev.match)
		if not stat or stat.size <= BIGFILE_THRESHOLD then return end
		vim.b[ev.buf].bigfile = true
		-- swapfile already globally disabled; just kill undo + syntax for big files
		vim.bo[ev.buf].undofile = false
		vim.bo[ev.buf].syntax = "OFF"
		vim.opt_local.foldmethod = "manual"
	end,
})

-- Highlight on yank (native vim.hl)
autocmd("TextYankPost", {
	group = augroup("HighlightYank", {}),
	pattern = "*",
	callback = function()
		vim.hl.on_yank({ higroup = "IncSearch", timeout = 40 })
	end,
})

-- Trim trailing whitespace on save (real files only — skip oil, fugitive, nofile bufs)
autocmd("BufWritePre", {
	group = augroup("TrimWhitespace", {}),
	pattern = "*",
	callback = function()
		if vim.bo.buftype ~= "" then return end -- skip special buffers
		vim.cmd([[%s/\s\+$//e]])
	end,
})

-- Assembly filetype
autocmd({ "BufNewFile", "BufRead" }, {
	pattern = "*.asm",
	callback = function() vim.bo.filetype = "asm" end,
})
