return {
	-- Theme — the ONLY eager plugin. Applies carbonfox right after it loads.
	{
		"EdenEast/nightfox.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("nightfox").setup({
				options = {
					compile_path = vim.fn.stdpath("cache") .. "/nightfox",
					compile_file_suffix = "_compiled",
					transparent = true,
					terminal_colors = true,
					dim_inactive = false,
					module_default = true,
					-- styles must be nested under options, not alongside it
					styles = { comments = "italic" },
					inverse = { match_paren = false, visual = false, search = true },
					modules = {
						cmp = true, diagnostic = true, native_lsp = true,
						treesitter = true, telescope = true, gitsigns = true,
						indent_blankline = true,
					},
				},
				groups = {
					all = {
						VertSplit = { fg = "#cccccc", bg = "NONE" },
						-- NormalFloat must NOT link to Normal when transparent=true —
						-- that would make floats transparent (same as terminal bg),
						-- making them invisible. Give floats the base bg color instead.
						NormalFloat = { bg = "palette.bg1" },
						FloatBorder = { fg = "palette.fg3", bg = "palette.bg1" },
						Pmenu = { fg = "palette.fg1", bg = "palette.bg1" },
						PmenuSel = { fg = "palette.fg0", bg = "palette.bg3", style = "bold" },
						CursorLine = { bg = "palette.bg2" },
						CursorLineNr = { fg = "palette.orange", style = "bold" },
						StatusLine = { fg = "palette.fg2", bg = "palette.bg1" },
						Visual = { bg = "palette.bg3" },
						DiagnosticError = { fg = "#ff5c57", style = "italic" },
						DiagnosticWarn = { fg = "#f3f99d", style = "italic" },
						DiagnosticInfo = { fg = "#57c7ff" },
						DiagnosticHint = { fg = "#9aedfe" },
					},
				},
			})
			pcall(vim.cmd.colorscheme, "carbonfox")
		end,
	},

	-- Indent guides (deferred until after startup)
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = "VeryLazy",
		config = function()
			local hooks = require("ibl.hooks")
			-- Ordered explicitly — vim.tbl_keys() returns keys in arbitrary Lua
			-- table order, which makes the indent level → color mapping random
			-- on every load.
			local highlight_names = {
				"RainbowRed", "RainbowYellow", "RainbowBlue", "RainbowOrange",
				"RainbowGreen", "RainbowViolet", "RainbowCyan",
			}
			local highlight_colors = {
				RainbowRed    = "#E06C75",
				RainbowYellow = "#E5C07B",
				RainbowBlue   = "#61AFEF",
				RainbowOrange = "#D19A66",
				RainbowGreen  = "#98C379",
				RainbowViolet = "#C678DD",
				RainbowCyan   = "#56B6C2",
			}
			hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
				for name, color in pairs(highlight_colors) do
					vim.api.nvim_set_hl(0, name, { fg = color })
				end
			end)
			require("ibl").setup({
				indent = { char = "┆", highlight = highlight_names },
			})
		end,
	},
}
