-- Local plugin: driftwood — a flexible floating-window shell. Its first
-- provider is the LSP document-symbol outline.
-- Code lives in lua/driftwood/; this spec just lazy-loads it on the `;` key.
return {
	"driftwood",
	dir = vim.fn.stdpath("config"),
	name = "driftwood",
	lazy = true,
	keys = { ";" }, -- lhs-only trigger; the real mapping is set in config()
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
