return {
  'mrjones2014/smart-splits.nvim',
  config = function()
    require("smart-splits").setup({
      at_edge = 'stop'
    })

    -- recommended mappings
    -- resizing splits
    -- these keymaps will also accept a range,
    -- for example `10<A-h>` will `resize_left` by `(10 * config.default_amount)`

    -- Move cursor between splits using Ctrl + hjkl
    local ss = require("smart-splits")
    vim.keymap.set('n', '<C-h>', ss.move_cursor_left, { desc = "Move cursor to left split" })
    vim.keymap.set('n', '<C-j>', ss.move_cursor_down, { desc = "Move cursor to lower split" })
    vim.keymap.set('n', '<C-k>', ss.move_cursor_up, { desc = "Move cursor to upper split" })
    vim.keymap.set('n', '<C-l>', ss.move_cursor_right, { desc = "Move cursor to right split" })

    -- Resize splits using Alt + hjkl
    vim.keymap.set('n', '<A-h>', ss.resize_left, { desc = "Resize split left" })
    vim.keymap.set('n', '<A-j>', ss.resize_down, { desc = "Resize split down" })
    vim.keymap.set('n', '<A-k>', ss.resize_up, { desc = "Resize split up" })
    vim.keymap.set('n', '<A-l>', ss.resize_right, { desc = "Resize split right" })

    -- Swap buffers between windows using <leader>w + hjkl
    vim.keymap.set('n', '<A-S-h>', ss.swap_buf_left, { desc = "Swap buffer left" })
    vim.keymap.set('n', '<A-S-j>', ss.swap_buf_down, { desc = "Swap buffer down" })
    vim.keymap.set('n', '<A-S-k>', ss.swap_buf_up, { desc = "Swap buffer up" })
    vim.keymap.set('n', '<A-S-l>', ss.swap_buf_right, { desc = "Swap buffer right" })
  end
}
