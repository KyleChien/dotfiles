return {
  "rose-pine/neovim",
  name = "rose-pine",
  priority = 1000, -- load before others to avoid flashing
  config = function()
    vim.cmd("colorscheme rose-pine") -- set the colorscheme
  end,
}
