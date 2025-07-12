return {
  -- {
  --
  --   "rose-pine/neovim",
  --   name = "rose-pine",
  --   priority = 1000, -- load before others to avoid flashing
  --   config = function()
  --     require("rose-pine").setup({
  --       styles = {
  --           bold = true,
  --           italic = false,
  --           transparency = false,
  --       },
  --     })
  --
  --     vim.cmd("colorscheme rose-pine") -- set the colorscheme
  --   end,
  -- },
  {
    "vague2k/vague.nvim",
    config = function()
      require("vague").setup({
        italic = false
      })
      vim.cmd("colorscheme vague") -- set the colorscheme
    end
  },
}
