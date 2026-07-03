-- Local plugin: LSP document-symbol outline in a floating window.
-- Code lives in lua/symboltree/; this spec just lazy-loads it on the `;` key.
return {
	"symboltree",
	dir = vim.fn.stdpath("config"),
	name = "symboltree",
	lazy = true,
	keys = { ";" }, -- lhs-only trigger; the real mapping is set in config()
	config = function()
		require("symboltree").setup()
	end,
}
