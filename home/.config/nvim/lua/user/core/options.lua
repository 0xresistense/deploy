local opt = vim.opt

-- netrw is disabled (oil is the file explorer); keep the guard
vim.g.loaded_netrwPlugin = 1

-- No plugin here uses a Node/Perl/Python3/Ruby remote-plugin host — disable
-- the providers outright rather than let checkhealth probe for them (and
-- warn about missing pynvim/cpan modules/etc) on every startup.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

opt.guicursor = "v-c:block,i:ver25"

opt.number = true
opt.relativenumber = true

opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true
opt.wrap = true
-- Cap legacy regex syntax highlighting per line (helps pathological
-- single-huge-line files, e.g. minified bundles, on top of the bigfile guard).
opt.synmaxcol = 500

-- undofile is the real safety net for crash recovery; swapfile buys nothing
-- on top of it and only causes write-latency spikes on large files (each
-- keystroke flushes the swap). Disable swap, keep undo.
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = os.getenv("HOME") .. "/.vim/undodir"

opt.hlsearch = false
opt.incsearch = true

opt.termguicolors = true
opt.scrolloff = 3
opt.signcolumn = "yes"
opt.isfname:append("@-@")
opt.updatetime = 50
opt.colorcolumn = "92"
-- Set rounded border for all floating windows (LSP hover, signature, diagnostics).
-- This is the correct 0.12+ API — vim.o.winborder is read by open_floating_preview
-- and all lsp.util floats; no handler patching needed.
opt.winborder = "rounded"

-- Project-local .nvim.lua (trust-prompted). Per-project overrides, zero plugin.
opt.exrc = true

-- Ensure undodir exists (swap/backup are disabled).
do
	local undodir = opt.undodir:get()[1]
	if vim.fn.isdirectory(undodir) == 0 then
		vim.fn.mkdir(undodir, "p")
	end
end
