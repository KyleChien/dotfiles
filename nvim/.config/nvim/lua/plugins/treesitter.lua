return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = ":TSUpdate",
	config = function()
		require("nvim-treesitter").install({
			"json",
			"lua",
			"luadoc",
			"luap",
			"markdown",
			"markdown_inline",
			"python",
			"regex",
			"toml",
			"vim",
			"vimdoc",
			"xml",
			"yaml",
		})

		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "json", "lua", "python", "markdown", "yaml", "toml", "xml" },
			callback = function()
				vim.treesitter.start()
			end,
		})
	end,
}
