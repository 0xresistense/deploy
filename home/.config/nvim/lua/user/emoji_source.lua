-- blink.cmp source: ":name" emoji completion using Claude Code's own name→emoji table
-- (extracted from the claude binary into data/emoji.json) so names match claude-cli.
local M = {}

local names -- sorted list of {name, emoji}, loaded lazily

local function load()
	if names then return names end
	local path = vim.fn.stdpath("config") .. "/lua/user/data/emoji.json"
	local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
	names = {}
	if not ok then return names end
	for name, emoji in pairs(data) do names[#names + 1] = { name = name, emoji = emoji } end
	table.sort(names, function(a, b) return a.name < b.name end)
	return names
end

function M.new() return setmetatable({}, { __index = M }) end

function M:get_trigger_characters() return { ":" } end

function M:get_completions(ctx, callback)
	local before = " " .. ctx.line:sub(1, ctx.cursor[2])
	local query = before:match("%s:([%w_+-]+)$")
	if not query then return callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false }) end
	local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
	local items = {}
	for _, e in ipairs(load()) do
		items[#items + 1] = {
			label = e.emoji .. " :" .. e.name .. ":",
			filterText = e.name,
			kind = require("blink.cmp.types").CompletionItemKind.Text,
			textEdit = {
				newText = e.emoji,
				range = { start = { line = row, character = col - #query - 1 }, ["end"] = { line = row, character = col } },
			},
		}
	end
	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return M
