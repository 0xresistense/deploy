vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set
local runner = require("user.core.runner")

-- Clipboard
map({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
map("n", "<leader>Y", [["+Y]])
map({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete without yanking" })
map("x", "<leader>p", [["_dP]], { desc = "Paste over selection, keep register" })

-- Move selected lines
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Keep cursor centered
map("n", "J", "mzJ`z")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Insert-mode escape, disable Ex
map("i", "<C-c>", "<Esc>")
map("n", "Q", "<nop>")

-- tmux sessionizer
map("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

-- Quickfix / location list
map("n", "<C-k>", "<cmd>cnext<CR>zz")
map("n", "<C-j>", "<cmd>cprev<CR>zz")
map("n", "<leader>k", "<cmd>lnext<CR>zz")
map("n", "<leader>j", "<cmd>lprev<CR>zz")

-- Search/replace word under cursor
map("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- Make file executable
map("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-- Source current file
map("n", "<leader><leader>", function() vim.cmd("so") end)

-- Native commenting (replaces vim-commentary) — identical behavior
map("n", "<leader>c", "gcc", { remap = true, desc = "Toggle comment line" })
map("x", "<leader>c", "gc", { remap = true, desc = "Toggle comment selection" })

-- Window navigation
map("n", "<leader>H", "<C-w>h", { silent = true })
map("n", "<leader>J", "<C-w>j", { silent = true })
map("n", "<leader>K", "<C-w>k", { silent = true })
map("n", "<leader>L", "<C-w>l", { silent = true })

-- Tabs
map("n", "<A-t>", function() vim.cmd("tabnew") end, { silent = true })
map("n", "<A-n>", "<cmd>tabnext<CR>", { silent = true })
map("n", "<A-p>", "<cmd>tabprevious<CR>", { silent = true })

-- Redo
map("n", "<S-u>", "<C-r>", { silent = true })

-- Diagnostics float
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostics float" })

-- Copy relative path
map("n", "<leader>z", function()
	local full = vim.api.nvim_buf_get_name(0)
	local cwd = vim.fn.getcwd()
	if not full:find(cwd, 1, true) then return end
	local rel = full:sub(#cwd + 2)
	vim.fn.setreg("+", rel)
	vim.api.nvim_echo({ { "Copied path: " .. rel, "None" } }, false, {})
end, { desc = "Copy relative path", silent = true })

-- Native runner
map("n", "<leader>rr", runner.run_file,     { desc = "Run file" })
map("n", "<leader>rft", runner.run_file_tab, { desc = "Run file in tab" })
map("n", "<leader>rp", runner.run_project,  { desc = "Run project" })

-- File explorer (was netrw :Ex -> oil) and plugin manager
map("n", "<leader>pv", "<cmd>Oil<CR>", { desc = "Open file explorer (oil)" })
map("n", "<leader>vpp", "<cmd>Lazy<CR>", { desc = "Plugin manager" })
