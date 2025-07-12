vim.g.mapleader = " "

local keymap = vim.keymap

vim.keymap.set("n", ";", ":", { desc = "Quick command" })

-- Clear search and stop snippet on escape
keymap.set({ "i", "n", "s" }, "<esc>", function()
  vim.cmd("noh")
  return "<esc>"
end, { expr = true, desc = "Escape and Clear hlsearch" })

-- better up/down
keymap.set({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
keymap.set({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
keymap.set({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
keymap.set({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

-- Move to window using the <ctrl> hjkl keys
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window", noremap = true })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window", noremap = true })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window", noremap = true })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", noremap = true })

-- Resize window using <ctrl> arrow keys
keymap.set("n", "_", "<cmd>resize -2<cr>", { desc = "Decrease Window Height" })
keymap.set("n", "+", "<cmd>resize +2<cr>", { desc = "Increase Window Height" })
keymap.set("n", "-", "<cmd>vertical resize -2<cr>", { desc = "Decrease Window Width" })
keymap.set("n", "=", "<cmd>vertical resize +2<cr>", { desc = "Increase Window Width" })

-- Move Lines
keymap.set("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
keymap.set("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
keymap.set("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
keymap.set("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
keymap.set("v", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
keymap.set("v", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })

-- Search
keymap.set("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
keymap.set("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
keymap.set("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
keymap.set("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
keymap.set("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })
keymap.set("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

-- better indenting
keymap.set("v", "<", "<gv")
keymap.set("v", ">", ">gv")

-- Select all
keymap.set("n", "<C-a>", "gg<S-v>G", { noremap = true, silent = true })

-- In normal mode: save the file
keymap.set("n", "<C-s>", ":w<CR>", { noremap = true, silent = true })

-- In insert mode: exit insert mode, save, then return to insert mode
keymap.set("i", "<C-s>", "<Esc>:w<CR>i", { noremap = true, silent = true })

-- Move to start/end of line
keymap.set({ "n", "x", "o" }, "H", "^", { noremap = true, silent = true })
keymap.set({ "n", "x", "o" }, "L", "g_", { noremap = true, silent = true })

-- Paste without overwriting register
keymap.set("v", "p", '"_dp')
keymap.set("v", "P", '"_dP')

-- window management
keymap.set("n", "<leader>wv", "<C-w>v", { desc = "Split window vertically" })
keymap.set("n", "<leader>wh", "<C-w>s", { desc = "Split window horizontally" })
keymap.set("n", "<leader>we", "<C-w>=", { desc = "Make splits equal size" })
keymap.set("n", "<leader>wq", "<cmd>close<CR>", { desc = "Close current split" })

-- better scroll
keymap.set({'n', 'v'}, '<C-d>', '<C-d>zz', { desc = 'Scroll downwards' })
keymap.set({'n', 'v'}, '<C-u>', '<C-u>zz', { desc = 'Scroll upwards' })
keymap.set({'n', 'v'}, '<C-n>', '}', { desc = 'Next paragraph' })
keymap.set({'n', 'v'}, '<C-p>', '{', { desc = 'Next paragraph' })

-- lsp
keymap.set("n", "<leader>fm", function() vim.lsp.buf.format() end, { desc = "Lsp format" })

-- disable substitude
keymap.set({ "n", "v" }, "s", "<Nop>", { noremap = true, silent = true })
