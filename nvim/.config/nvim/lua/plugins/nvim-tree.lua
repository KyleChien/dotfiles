return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("nvim-tree").setup {
      git = {
        enable = false
      },
      view = {
        width = 30,
        side = "left",
      },
    }

    -- Close all nvim tree windows before exit neovim
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        require("nvim-tree.api").tree.close()
      end,
    })

    -- keymap
    vim.keymap.set("n", "<leader>e", ":NvimTreeFindFile<CR>", { noremap = true, silent = true })
  end,
}
