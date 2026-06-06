return {
	{
		"nvim-mini/mini.splitjoin",
		version = false,
		config = function()
			require("mini.splitjoin").setup()
		end,
	},
	{
		"echasnovski/mini.pairs",
		version = false,
		config = function()
			require("mini.pairs").setup()
		end,
	},
	{
		"echasnovski/mini.surround",
		version = false,
		config = function()
			require("mini.surround").setup({})
		end,
	},
	{
		"nvim-mini/mini.clue",
		config = function()
			local miniclue = require("mini.clue")
			miniclue.setup({
				triggers = {
					-- Leader triggers
					{ mode = { "n", "x" }, keys = "<Leader>" },

					-- `[` and `]` keys
					{ mode = "n", keys = "[" },
					{ mode = "n", keys = "]" },

					-- -- Built-in completion
					-- { mode = 'i',          keys = '<C-x>' },
					--
					-- Marks
					{ mode = { "n", "x" }, keys = "'" },
					{ mode = { "n", "x" }, keys = "`" },

					-- Registers
					{ mode = { "n", "x" }, keys = '"' },
					{ mode = { "i", "c" }, keys = "<C-r>" },

					-- -- Window commands
					-- { mode = 'n',          keys = '<C-w>' },

					-- `g` key
					{ mode = { "n", "x" }, keys = "g" },

					-- `z` key
					{ mode = { "n", "x" }, keys = "z" },
				},

				window = { delay = 0 },

				clues = {
					-- Enhance this by adding descriptions for <Leader> mapping groups
					miniclue.gen_clues.square_brackets(),
					miniclue.gen_clues.builtin_completion(),
					miniclue.gen_clues.marks(),
					miniclue.gen_clues.registers(),
					miniclue.gen_clues.windows(),
					miniclue.gen_clues.g(),
					miniclue.gen_clues.z(),
				},
			})
		end,
	},
	{
		"nvim-mini/mini.files",
		version = false,
		config = function()
			require("mini.files").setup({
				mappings = {
					go_in = '',
					go_in_plus = ''
				},
				windows = {
					max_number = math.huge,
					preview = false,
					width_focus = 20,
					width_nofocus = 20,
					width_preview = 20,
				},
				options = {
					permanent_delete = false, -- safer: deletes go to trash
				},
			})

			-- 'l': enter directories only; do nothing on a file
			local l_go_in_dir = function()
				local entry = MiniFiles.get_fs_entry()
				if entry ~= nil and entry.fs_type == "directory" then
					MiniFiles.go_in()
				end
			end

			-- '<CR>': enter directories, or open file and close explorer
			local cr_smart = function()
				if MiniFiles.get_fs_entry() ~= nil then
					MiniFiles.go_in({ close_on_file = true })
				end
			end

			vim.api.nvim_create_autocmd("User", {
				pattern = "MiniFilesBufferCreate",
				callback = function(args)
					local buf = args.data.buf_id
					vim.keymap.set("n", "l", l_go_in_dir, { buffer = buf, desc = "Go in directory" })
					vim.keymap.set("n", "<CR>", cr_smart, { buffer = buf, desc = "Go in / open file" })
				end,
			})

			-- Open at the directory of the current file (falls back to cwd)
			vim.keymap.set("n", "<leader>e", function()
				if not MiniFiles.close() then
					MiniFiles.open(vim.api.nvim_buf_get_name(0))
				end
			end, { desc = "Mini File explorer" })
		end,
	},
}
