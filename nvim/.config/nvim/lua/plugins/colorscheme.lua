return {
	"vague2k/vague.nvim",
  version = "v2.1.0",
	config = function()
		require("vague").setup({
			italic = false,
		})
		vim.cmd("colorscheme vague") -- set the colorscheme
	end,
}
