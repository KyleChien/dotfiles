return {
  "yannvanhalewyn/jujutsu.nvim",
  dependencies = { "sindrets/diffview.nvim" },
  config = function()
    require("jujutsu-nvim").setup({
      diff_preset = "diffview",
    })
  end,
}
