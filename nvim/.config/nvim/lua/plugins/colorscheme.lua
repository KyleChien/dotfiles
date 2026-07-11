return {
	"vague2k/vague.nvim",
	version = "v2.1.0",
	config = function()
		require("vague").setup({
			italic = false,
			transparent = true,
			colors = {
				visual = "#4f4f66",
			},
		})
		vim.cmd("colorscheme vague")
	end,
}
