local M = {}

-- Build the run command for the current FILE based on its filetype.
local function file_cmd()
	local ft = vim.bo.filetype
	local file = vim.fn.expand("%:p")
	local dir = vim.fn.expand("%:p:h")
	local stem = vim.fn.expand("%:t:r")
	-- Use a per-file output path under /tmp to avoid collisions when two files
	-- share the same stem (e.g. two different main.c in different directories).
	local out = "/tmp/nvim-run-" .. vim.fn.sha256(file):sub(1, 8) .. "-" .. stem
	local q = vim.fn.shellescape
	local map = {
		javascript = "node " .. q(file),
		typescript = "deno run " .. q(file),
		python = "python3 -u " .. q(file),
		rust = "cargo run",
		lua = "lua " .. q(file),
		sh = "bash " .. q(file),
		go = "go run " .. q(file),
		c = string.format("cd %s && gcc %s -o %s && %s", q(dir), q(file), q(out), q(out)),
		cpp = string.format("cd %s && g++ %s -o %s && %s", q(dir), q(file), q(out), q(out)),
		java = string.format("cd %s && javac %s && java %s", q(dir), q(file), q(stem)),
	}
	return map[ft]
end

-- Build the run command for the current PROJECT based on root markers.
local function project_cmd()
	local root = vim.fn.getcwd()
	local exists = function(f) return vim.fn.filereadable(root .. "/" .. f) == 1 end
	if exists("Cargo.toml") then return "cargo run" end
	if exists("package.json") then return "npm start" end
	if exists("go.mod") then return "go run ." end
	if exists("Makefile") then return "make" end
	return nil
end

-- Open a terminal running `cmd`. where = "split" (default) | "tab".
-- cmd is already shell-escaped by file_cmd()/project_cmd() via shellescape(),
-- so pass it to the shell via termopen rather than string-concatenating it
-- into a vimscript :terminal call (which would double-interpret it).
local function run(cmd, where)
	if not cmd then
		vim.notify("No run command for this filetype/project", vim.log.levels.WARN)
		return
	end
	vim.cmd("silent! write")
	if where == "tab" then
		vim.cmd("tabnew")
	else
		vim.cmd("botright 15split")
	end
	-- Open a new empty buffer and start the terminal in it.
	local buf = vim.api.nvim_get_current_buf()
	-- termopen expects a shell command string; the individual args in
	-- file_cmd() are already shellescape()'d so passing via /bin/sh -c is safe.
	vim.fn.termopen({ "/bin/sh", "-c", cmd }, {
		on_exit = function(_, code)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					local label = code == 0 and "✓ done" or ("✗ exit " .. code)
					vim.api.nvim_buf_set_name(buf, label)
				end
			end)
		end,
	})
	vim.cmd("startinsert")
end

function M.run_file() run(file_cmd(), "split") end
function M.run_file_tab() run(file_cmd(), "tab") end
function M.run_project() run(project_cmd(), "split") end

return M
