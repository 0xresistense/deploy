local cmd = vim.api.nvim_create_user_command

cmd("CleanEmptyLines", function() vim.cmd([[%s/\(\n\s*\)\{2,}/\r\r/g]]) end, {})
cmd("TrimWhitespace", function() vim.cmd([[%s/\s\+$//e]]) end, {})

cmd("ReloadModule", function(opts)
	package.loaded[opts.args] = nil
	require(opts.args)
end, { nargs = 1, complete = "file" })

cmd("CopyPath", function()
	local path = vim.fn.expand("%:p")
	vim.fn.setreg("+", path)
	print("Copied path: " .. path)
end, {})

cmd("ToggleSpell", function() vim.wo.spell = not vim.wo.spell end, {})
cmd("StripComments", function()
	local patterns = {
		lua        = [[g/^\s*--/d]],
		javascript = [[g/^\s*\/\//d]],
		typescript = [[g/^\s*\/\//d]],
		javascriptreact = [[g/^\s*\/\//d]],
		typescriptreact = [[g/^\s*\/\//d]],
		python     = [[g/^\s*#/d]],
		sh         = [[g/^\s*#/d]],
		bash       = [[g/^\s*#/d]],
		go         = [[g/^\s*\/\//d]],
		rust       = [[g/^\s*\/\//d]],
		c          = [[g/^\s*\/\//d]],
		cpp        = [[g/^\s*\/\//d]],
	}
	local ft = vim.bo.filetype
	local pat = patterns[ft]
	if not pat then
		vim.notify("StripComments: unsupported filetype '" .. ft .. "'", vim.log.levels.WARN)
		return
	end
	vim.cmd(pat)
end, {})

cmd("TodoList", function()
	-- Exclude node_modules and other noise dirs. vimgrep's **/* glob has no
	-- built-in exclude, so pre-build the file list with glob() and filter it.
	local files = vim.fn.glob("**/*.{js,ts,jsx,tsx,lua,py,go,rs,c,cpp,sh,md}", false, true)
	local filtered = vim.tbl_filter(function(f)
		return not f:match("node_modules") and not f:match("%.git")
	end, files)
	if #filtered == 0 then
		vim.notify("No files to search", vim.log.levels.WARN)
		return
	end
	vim.fn.setqflist({})
	vim.cmd("vimgrep /TODO\\|FIXME\\|NOTE/ " .. table.concat(
		vim.tbl_map(function(f) return vim.fn.fnameescape(f) end, filtered), " "
	))
	vim.cmd("copen")
end, {})

cmd("EditConfig", function() vim.cmd("edit $MYVIMRC") end, {})
cmd("ReloadConfig", function()
	-- Sourcing $MYVIMRC re-executes init.lua without clearing loaded modules,
	-- which double-registers every autocmd, keymap, and command. Instead clear
	-- the user.* module cache and re-require — keeps lazy.nvim untouched.
	for k in pairs(package.loaded) do
		if k:match("^user") then package.loaded[k] = nil end
	end
	dofile(vim.env.MYVIMRC)
	vim.notify("Config reloaded", vim.log.levels.INFO)
end, {})

cmd("ToggleHL", function() vim.o.hlsearch = not vim.o.hlsearch end, {})
cmd("TabsToSpaces", function() vim.cmd([[retab]]) end, {})
cmd("DedupLines", function() vim.cmd([[%!awk '!seen[$0]++']]) end, {})

cmd("FileStats", function()
	local s = vim.fn.wordcount()
	print(string.format("Lines: %d | Words: %d | Chars: %d", s.lines or 0, s.words, s.chars))
end, {})

cmd("WhichFile", function() print(vim.fn.expand("%:p")) end, {})
cmd("YankAll", function()
	vim.cmd(":%y+")
	print("Buffer yanked to system clipboard")
end, {})

cmd("CloseHidden", function()
	-- Close buffers that are: loaded, not modified, not visible in any window.
	local visible = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		visible[vim.api.nvim_win_get_buf(win)] = true
	end
	local closed = 0
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf)
			and not vim.bo[buf].modified
			and not visible[buf]
		then
			vim.api.nvim_buf_delete(buf, { force = false })
			closed = closed + 1
		end
	end
	vim.notify(string.format("Closed %d hidden buffer(s)", closed), vim.log.levels.INFO)
end, {})

-- Render the mermaid fence under the cursor (or the first one in the buffer)
-- to a PNG via mmdc and open it in feh. On-demand, no background process —
-- the deliberate alternative to inline image.nvim/ueberzugpp rendering.
cmd("RenderMermaid", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)[1]

	local start_line
	for i = cursor, 1, -1 do
		if lines[i]:match("^```mermaid%s*$") then
			start_line = i
			break
		elseif i < cursor and lines[i]:match("^```%s*$") then
			break
		end
	end
	if not start_line then
		for i, l in ipairs(lines) do
			if l:match("^```mermaid%s*$") then
				start_line = i
				break
			end
		end
	end
	if not start_line then
		vim.notify("No mermaid code block found", vim.log.levels.WARN)
		return
	end

	local end_line
	for i = start_line + 1, #lines do
		if lines[i]:match("^```%s*$") then
			end_line = i
			break
		end
	end
	if not end_line then
		vim.notify("Unclosed mermaid code block", vim.log.levels.WARN)
		return
	end

	local body = table.concat(lines, "\n", start_line + 1, end_line - 1)
	-- stdpath("cache"), NOT tempname() — tempname() lives under nvim's session
	-- tmpdir, which gets deleted on :qa, potentially out from under the viewer.
	local cache_dir = vim.fn.stdpath("cache") .. "/mermaid"
	vim.fn.mkdir(cache_dir, "p")
	local stamp = os.date("%Y%m%d-%H%M%S")
	local tmp_mmd = cache_dir .. "/" .. stamp .. ".mmd"
	local tmp_png = cache_dir .. "/" .. stamp .. ".png"
	vim.fn.writefile(vim.split(body, "\n"), tmp_mmd)

	vim.notify("Rendering mermaid diagram...", vim.log.levels.INFO)
	vim.system(
		-- PNG via mmdc's real Chromium rendering pass, NOT SVG. Mermaid renders
		-- its text as <foreignObject><div xmlns="...xhtml">, not native SVG
		-- <text> — librsvg (which both feh/imlib2 and qView/QtSvg ultimately use)
		-- doesn't render foreignObject HTML at all, so SVG output showed shapes
		-- with every label silently dropped. -s 4 asks Chromium itself for a
		-- 4x-DPI screenshot (real anti-aliased text at that resolution, not an
		-- upscale) for real zoom headroom without losing any text.
		{ "mmdc", "-i", tmp_mmd, "-o", tmp_png, "-b", "transparent", "-s", "4" },
		{ text = true },
		function(res)
			vim.schedule(function()
				if res.code ~= 0 then
					vim.notify("mmdc failed: " .. (res.stderr or "unknown error"), vim.log.levels.ERROR)
					return
				end
				vim.system({ "qview", tmp_png }, { detach = true })
			end)
		end
	)
end, {})
