-- True while the text before the cursor is a word-start ":xx" emoji query.
local function is_emoji_ctx(ctx)
	local before = " " .. ctx.line:sub(1, ctx.cursor[2]) -- leading space: ":" at column 0 counts as word start
	return before:match("%s:[%w_+-][%w_+-]+$") ~= nil
end

return {
	"saghen/blink.cmp",
	version = "v1.10.2", -- prebuilt binary; exact pin prevents pulling a binary built for a different nvim ABI
	event = { "InsertEnter", "CmdlineEnter" },
	---@module 'blink.cmp'
	opts = {
		keymap = {
			preset = "none", -- exact replication of the old nvim-cmp keys
			["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-e>"] = { "hide", "fallback" },
			["<C-p>"] = { "select_prev", "fallback" },
			["<C-n>"] = { "select_next", "fallback" },
			["<CR>"] = { "select_and_accept", "fallback" },
			["<C-y>"] = { "select_and_accept", "fallback" },
			["<C-u>"] = { "scroll_documentation_up", "fallback" },
			["<C-d>"] = { "scroll_documentation_down", "fallback" },
		},
		completion = {
			-- OFF by default: menu only appears on <C-space> (or ':xx' for emoji). Toggle per-buffer with <leader>ta.
			-- Exception: typing ":xx" (2+ chars) auto-opens the menu for emoji.
			menu = {
				auto_show = function(ctx) return vim.b.blink_auto == true or is_emoji_ctx(ctx) end,
				-- Emoji context: bare "😃 :smiley:" rows (no kind icon), like claude-cli's picker.
				draw = {
					columns = function(ctx)
						if is_emoji_ctx(ctx) then return { { "label" } } end
						return { { "kind_icon" }, { "label", "label_description", gap = 1 } }
					end,
				},
			},
			-- The info/doc box for the selected item (like old nvim-cmp's bordered docs).
			-- Menu stays manual (<C-Space>); once it's open, docs appear automatically.
			documentation = { auto_show = true, auto_show_delay_ms = 200 },
			list = { selection = { preselect = true, auto_insert = false } },
		},
		-- friendly-snippets dropped; LSP-provided snippets still expand via native vim.snippet.
		sources = {
			default = { "lsp", "path", "buffer", "emoji" },
			providers = {
				emoji = { module = "user.emoji_source", name = "Emoji", score_offset = 15 },
			},
		},
		snippets = { preset = "default" }, -- native vim.snippet
		fuzzy = { implementation = "rust" },
		signature = { enabled = true },
	},
	config = function(_, opts)
		require("blink.cmp").setup(opts)
		-- <leader>ta: toggle auto-show (was the cmp autocomplete toggle)
		vim.keymap.set("n", "<leader>ta", function()
			vim.b.blink_auto = not vim.b.blink_auto
			print("Autocomplete auto-show: " .. (vim.b.blink_auto and "ON" or "OFF (manual)"))
		end, { desc = "Toggle completion auto-show" })
	end,
}
