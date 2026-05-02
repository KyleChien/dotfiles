return {
	"vague2k/vague.nvim",
	config = function()
		require("vague").setup({
			italic = false,
		})
		vim.cmd("colorscheme vague") -- set the colorscheme
	end,
}
