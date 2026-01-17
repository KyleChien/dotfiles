vim.g.mapleader = " "
vim.keymap.set("n", ";", ":", { desc = "Quick command" })

-- Clear search and stop snippet on escape
vim.keymap.set({ "i", "n", "s" }, "<esc>", function()
  vim.cmd("noh")
  return "<esc>"
end, { expr = true, desc = "Escape and Clear hlsearch" })

-- better up/down
vim.keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
vim.keymap.set({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

-- -- Move to window using the <ctrl> hjkl keys
-- vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window", noremap = true })
-- vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window", noremap = true })
-- vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window", noremap = true })
-- vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", noremap = true })

-- -- Resize window using <ctrl> arrow keys
-- vim.keymap.set("n", "_", "<cmd>resize -2<cr>", { desc = "Decrease Window Height" })
-- vim.keymap.set("n", "+", "<cmd>resize +2<cr>", { desc = "Increase Window Height" })
-- vim.keymap.set("n", "-", "<cmd>vertical resize -2<cr>", { desc = "Decrease Window Width" })
-- vim.keymap.set("n", "=", "<cmd>vertical resize +2<cr>", { desc = "Increase Window Width" })

-- -- Move Lines
-- vim.keymap.set("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
-- vim.keymap.set("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
-- vim.keymap.set("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
-- vim.keymap.set("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
-- vim.keymap.set("v", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
-- vim.keymap.set("v", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })

-- Search
vim.keymap.set("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
vim.keymap.set("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
vim.keymap.set("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
vim.keymap.set("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
vim.keymap.set("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })
vim.keymap.set("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

-- better indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Select all
vim.keymap.set("n", "<C-a>", "gg<S-v>G", { noremap = true, silent = true })

-- In normal mode: save the file
vim.keymap.set("n", "<C-s>", ":w<CR>", { noremap = true, silent = true })

-- In insert mode: exit insert mode, save, then return to insert mode
vim.keymap.set("i", "<C-s>", "<Esc>:w<CR>i", { noremap = true, silent = true })

-- Move to start/end of line
vim.keymap.set({ "n", "x", "o" }, "H", "^", { noremap = true, silent = true })
vim.keymap.set({ "n", "x", "o" }, "L", "g_", { noremap = true, silent = true })

-- Paste without overwriting register
vim.keymap.set("v", "p", '"_dp')
vim.keymap.set("v", "P", '"_dP')

-- window management
vim.keymap.set("n", "<leader>wv", function() vim.cmd("vsplit") end, { desc = "Split window vertically" })
vim.keymap.set("n", "<leader>ws", function() vim.cmd("split") end, { desc = "Split window horizontally" })
vim.keymap.set("n", "<leader>w=", function() vim.cmd("wincmd =") end, { desc = "Make splits equal size" })
vim.keymap.set("n", "<leader>wq", function() vim.cmd("close") end, { desc = "Close current split" })

-- better scroll
vim.keymap.set({ "n", "v" }, "<C-d>", "<C-d>zz", { desc = "Scroll downwards" })
vim.keymap.set({ "n", "v" }, "<C-u>", "<C-u>zz", { desc = "Scroll upwards" })
vim.keymap.set({ "n", "v" }, "<C-n>", "}", { desc = "Next paragraph" })
vim.keymap.set({ "n", "v" }, "<C-p>", "{", { desc = "Next paragraph" })

-- lsp
vim.keymap.set("n", "<leader>fm", function() vim.lsp.buf.format() end, { desc = "Lsp format" })

-- disable substitude
vim.keymap.set({ "n", "v" }, "s", "<Nop>", { noremap = true, silent = true })

-- spliter
local function insert_commented_splitter_below()
  local total_width = 80
  local pad_char = "="

  local title = vim.fn.input("Splitter title: ")
  if title == "" then return end

  -- Get commentstring (e.g. "// %s", "# %s", "-- %s")
  local cs = vim.bo.commentstring
  if cs == "" or not cs:find("%%s") then
    cs = "%s"
  end

  -- Extract comment prefix
  local prefix = cs:match("^(.*)%%s") or ""
  prefix = prefix:gsub("%s*$", "") .. " "

  local available = total_width - #prefix
  local title_with_spaces = " " .. title .. " "
  local padding = available - #title_with_spaces

  local line
  if padding < 0 then
    line = prefix .. title
  else
    local left = math.floor(padding / 2)
    local right = padding - left
    line = prefix
        .. string.rep(pad_char, left)
        .. title_with_spaces
        .. string.rep(pad_char, right)
  end

  -- Insert BELOW cursor
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, { line })

  -- Move cursor to the inserted line (optional but nice)
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
end

vim.keymap.set("n", "<leader>=", insert_commented_splitter_below, {
  noremap = true,
  silent = true,
  desc = "Insert centered commented splitter below",
})
