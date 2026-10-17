-- UPPERCASE mode indicator
vim.o.statusline = table.concat({
  " %<", -- Truncate long paths
  "%#StatusLine#",
  "%f ", -- File path
  "%m",  -- Modified [+]
  "%r",  -- Readonly
  "%=",  -- Right align
  "%{exists('*FugitiveHead') && FugitiveHead() != '' ? ' ' . FugitiveHead() . ' ' : ''}", -- Git branch (Fugitive, guarded for lazy-load)
  "%y ", -- Filetype
  "%{&fileencoding?&fileencoding:&encoding} ", -- Encoding
  "%{&fileformat} ", -- File format (unix, dos, mac)
  "%#StatusLine# %l:%c ", -- Line:Col
  "%p%% ", -- Progress
}, "")
