-- Local plugin: driftwood — a flexible floating-window shell. Its providers are
-- the LSP document-symbol outline (`;`) and the file tree (`,`).
-- Code lives in lua/driftwood/; this spec just lazy-loads it on those keys.
return {
	"driftwood",
	dir = vim.fn.stdpath("config"),
	name = "driftwood",
	lazy = true,
	keys = { ";", "," }, -- lhs-only triggers; the real mappings are set in config()
	opts = {
		providers = {
			symbols = {
				initial_depth = 1,
			},
		},
	},
	config = function(_, opts)
		require("driftwood").setup(opts)
	end,
}
