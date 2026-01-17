return {
  'mrjones2014/smart-splits.nvim',
  config = function()
    require("smart-splits").setup({})
    -- recommended mappings
    -- resizing splits
    -- these keymaps will also accept a range,
    -- for example `10<A-h>` will `resize_left` by `(10 * config.default_amount)`

    -- Resize splits using Alt + hjkl
    vim.keymap.set('n', '<A-h>', require('smart-splits').resize_left, { desc = "Resize split left" })
    vim.keymap.set('n', '<A-j>', require('smart-splits').resize_down, { desc = "Resize split down" })
    vim.keymap.set('n', '<A-k>', require('smart-splits').resize_up, { desc = "Resize split up" })
    vim.keymap.set('n', '<A-l>', require('smart-splits').resize_right, { desc = "Resize split right" })

    -- Move cursor between splits using Ctrl + hjkl
    vim.keymap.set('n', '<C-h>', require('smart-splits').move_cursor_left, { desc = "Move cursor to left split" })
    vim.keymap.set('n', '<C-j>', require('smart-splits').move_cursor_down, { desc = "Move cursor to lower split" })
    vim.keymap.set('n', '<C-k>', require('smart-splits').move_cursor_up, { desc = "Move cursor to upper split" })
    vim.keymap.set('n', '<C-l>', require('smart-splits').move_cursor_right, { desc = "Move cursor to right split" })
    vim.keymap.set('n', '<C-\\>', require('smart-splits').move_cursor_previous,
      { desc = "Move cursor to previous split" })

    -- Swap buffers between windows using <leader>w + hjkl
    vim.keymap.set('n', '<leader>wh', require('smart-splits').swap_buf_left, { desc = "Swap buffer left" })
    vim.keymap.set('n', '<leader>wj', require('smart-splits').swap_buf_down, { desc = "Swap buffer down" })
    vim.keymap.set('n', '<leader>wk', require('smart-splits').swap_buf_up, { desc = "Swap buffer up" })
    vim.keymap.set('n', '<leader>wl', require('smart-splits').swap_buf_right, { desc = "Swap buffer right" })
  end
}
