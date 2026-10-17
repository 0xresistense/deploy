return {
	-- Mason = installer ONLY. Lazy on :Mason. NOT loaded at startup.
	{
		"mason-org/mason.nvim",
		cmd = { "Mason", "MasonInstall", "MasonUpdate", "MasonUninstall", "MasonLog" },
		opts = {},
	},

	-- Native LSP via nvim-lspconfig's config defaults (NO setup() calls).
	{
		"neovim/nvim-lspconfig",
		-- BufReadPost (not BufReadPre): buffer is already displayed before LSP starts
		-- loading + spawning the server. Moves the CPU spike off the critical path
		-- so the file appears immediately; LSP attaches ~100ms later.
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			-- Kill LSP log noise. Default is WARN which still dumps megabytes of
			-- tailwind tsconfig-parse errors into lsp.log. ERROR only logs actual
			-- failures that need attention.
			vim.lsp.log.set_level("ERROR")

			-- Make Mason-installed servers discoverable without loading the Mason plugin.
			vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH

			-- Diagnostics presentation.
			vim.diagnostic.config({
				virtual_text = { prefix = "●" },
				signs = true,
				underline = true,
				update_in_insert = false,
				severity_sort = true,
				float = { source = true }, -- border comes from vim.o.winborder globally
			})

			-- Completion capabilities from blink.cmp (loads blink at first file open).
			local caps = vim.lsp.protocol.make_client_capabilities()
			local ok, blink = pcall(require, "blink.cmp")
			if ok then caps = blink.get_lsp_capabilities(caps) end
			vim.lsp.config("*", { capabilities = caps })

			-- Float borders are set globally via vim.o.winborder = "rounded" in options.lua.
			-- No handler patching needed (vim.lsp.with is deprecated in 0.12).

			-- Per-server overrides (defaults come from nvim-lspconfig's lsp/*.lua).
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
						telemetry = { enable = false },
					},
				},
			})

			vim.lsp.config("rust_analyzer", {
				settings = {
					["rust-analyzer"] = {
						cargo = { allFeatures = true },
						check = { command = "clippy" },
						procMacro = { enable = true },
						inlayHints = { chainingHints = { enable = true } },
					},
				},
			})

			-- basedpyright: openFilesOnly avoids scanning the whole venv on attach.
			vim.lsp.config("basedpyright", {
				settings = {
					basedpyright = {
						analysis = {
							typeCheckingMode = "standard",
							diagnosticMode = "openFilesOnly",
						},
					},
				},
			})

			-- tailwindcss-language-server walks UP from the file looking for a
			-- tailwind.config.*, then treats THAT directory as workspace root and
			-- crawls everything under it — including every tsconfig.json across
			-- every sub-project. In a deep monorepo like
			-- /work/eshkon/altus/projects/{hoc-mvp,shadcn-mono,...} this triggers
			-- hundreds of tsconfig parses all at 03:08:28 (confirmed in lsp.log).
			--
			-- Fix: only root at a directory that DIRECTLY contains a tailwind
			-- config, never climbing past it into a parent repo root.
			-- Also drop markdown/mdx from filetypes (JSX-in-docs setup causes
			-- tailwind to attach on every .md file even in non-Tailwind projects).
			local tw_cfg = vim.lsp.config["tailwindcss"]
			if tw_cfg then
				vim.lsp.config("tailwindcss", {
					filetypes = tw_cfg.filetypes and vim.tbl_filter(function(ft)
						return ft ~= "markdown" and ft ~= "mdx"
					end, tw_cfg.filetypes) or nil,
					root_dir = function(bufnr, on_dir)
						local root = vim.fs.root(bufnr, {
							"tailwind.config.js", "tailwind.config.ts",
							"tailwind.config.cjs", "tailwind.config.mjs",
						})
						if root then on_dir(root) end
					end,
				})
			end

			-- ts_ls root_dir strategy for monorepos:
			--
			-- Default walks up to the nearest lock-file / .git — in a turborepo
			-- that's the repo root, so tsserver indexes every package at once
			-- (measured: 2 procs at 7-14% CPU, multi-second hangs on file open).
			--
			-- Fix: prefer the NEAREST package.json (the workspace package the
			-- file lives in). Only fall back to lock/git root for plain repos.
			--
			-- disableDynamicFileLists goes in `settings` (a tsserver JSON config
			-- option), NOT in init_options. init_options are ts-language-server
			-- wrapper flags; settings are forwarded to tsserver itself.
			vim.lsp.config("ts_ls", {
				root_dir = function(bufnr, on_dir)
					local deno_root = vim.fs.root(bufnr, { "deno.json", "deno.jsonc", "deno.lock" })
					local pkg_root  = vim.fs.root(bufnr, { "package.json" })
					local lock_root = vim.fs.root(bufnr, {
						"package-lock.json", "yarn.lock", "pnpm-lock.yaml",
						"pnpm-workspace.yaml", "bun.lockb", "bun.lock", ".git",
					})
					-- Bail if this looks like a Deno project.
					if deno_root and (not pkg_root or #deno_root >= #pkg_root) then return end
					local root = pkg_root or lock_root
					if root then on_dir(root) end
				end,
				init_options = {
					-- typescript-language-server wrapper flags (not tsserver flags).
					-- Disable the typings installer — it spawns a background process
					-- that tries to download @types/* for every lib it sees.
					disableAutomaticTypingAcquisition = true,
				},
				settings = {
					typescript = {
						-- tsserver JSON config options go here, not in init_options.
						-- disableDynamicFileLists: stop tsserver from crawling the
						-- project tree upfront; files are added as you open them.
						disableDynamicFileLists = true,
					},
					javascript = {
						disableDynamicFileLists = true,
					},
				},
			})

			-- Enable servers (started lazily when a matching buffer opens).
			vim.lsp.enable({
				"lua_ls", "rust_analyzer", "clangd", "basedpyright",
				"gopls", "ts_ls", "bashls", "tailwindcss",
			})

			-- Buffer-local LSP keymaps — the single place for all LSP maps.
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("user.lsp.attach", {}),
				callback = function(ev)
					if vim.b[ev.buf].bigfile then
						vim.schedule(function()
							pcall(vim.lsp.buf_detach_client, ev.buf, ev.data.client_id)
						end)
						return
					end
					local function bmap(mode, lhs, rhs, desc)
						vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, silent = true, desc = desc })
					end
					local has_fzf, fzf = pcall(require, "fzf-lua")
					if has_fzf then
						bmap("n", "gd",        fzf.lsp_definitions,       "Definitions")
						bmap("n", "gi",        fzf.lsp_implementations,   "Implementations")
						bmap("n", "gr",        fzf.lsp_references,        "References")
						bmap("n", "<leader>vws", fzf.lsp_workspace_symbols, "Workspace Symbols")
					else
						bmap("n", "gd",        vim.lsp.buf.definition,        "Definitions")
						bmap("n", "gi",        vim.lsp.buf.implementation,    "Implementations")
						bmap("n", "gr",        vim.lsp.buf.references,        "References")
						bmap("n", "<leader>vws", vim.lsp.buf.workspace_symbol, "Workspace Symbols")
					end
					bmap("n", "gD",          vim.lsp.buf.declaration,    "Declaration")
					bmap("n", "K",           vim.lsp.buf.hover,          "Hover")
					bmap("n", "<leader>vd",  vim.diagnostic.open_float,  "Line Diagnostics")
					bmap("n", "<leader>vca", vim.lsp.buf.code_action,    "Code Action")
					bmap("n", "<leader>vrn", vim.lsp.buf.rename,         "Rename")
					bmap("i", "<C-h>",       vim.lsp.buf.signature_help, "Signature Help")
					bmap("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Prev Diagnostic")
					bmap("n", "]d", function() vim.diagnostic.jump({ count = 1,  float = true }) end, "Next Diagnostic")
				end,
			})
		end,
	},
}
