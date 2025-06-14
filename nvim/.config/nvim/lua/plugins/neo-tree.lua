return {
  {
    "mrbjarksen/neo-tree-diagnostics.nvim",
    requires = "nvim-neo-tree/neo-tree.nvim",
    module = "neo-tree.sources.diagnostics", -- if wanting to lazyload
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      require("neo-tree").setup({
        enable_git_status = false,
        enable_diagnostics = false,
        window = {
          width = 30,
          mappings = {
            ["l"] = "open",
            ["h"] = "close_node",
            ["<space>"] = "none",
          },
          border = "none",
        },
        sources = { "filesystem", "document_symbols", "diagnostics" },
        source_selector = {
          winbar = false,
          statusline = false
        },

        -- Harpoon index
        filesystem = {
          components = {
            arrow_index = function(config, node, _)
              local node_path = node:get_id()
              local node_name = vim.fn.fnamemodify(node_path, ":t")
              local arrow_paths = vim.g.arrow_filenames

              if arrow_paths then
                for i, arrow_path in ipairs(arrow_paths) do
                  local arrow_name = vim.fn.fnamemodify(arrow_path, ":t")
                  if node_name == arrow_name then
                    return {
                      text = string.format(" ➤ %d", i),
                      highlight = config.highlight or "NeoTreeDirectoryIcon",
                    }
                  end
                end
              end

              return {}
            end
          },

          renderers = {
            file = {
              { "icon" },
              { "name" },
              { "arrow_index" },
              { "diagnostics" },
            },
          },
        },
      })

      -- Close all Neo-tree windows before exit neovim
      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
          require("neo-tree.command").execute({ action = "close" })
        end,
      })

      -- keymap
      vim.keymap.set("n", "<leader>e", function()
        vim.cmd("Neotree filesystem reveal left")
      end, { desc = "NeoTree: Reveal document symbols (left)" })

      vim.keymap.set("n", "<leader>s", function()
        vim.cmd("Neotree document_symbols reveal right")
      end, { desc = "NeoTree: Reveal document symbols (right)" })

      vim.keymap.set("n", "<leader>d", function()
        vim.cmd("Neotree diagnostics reveal bottom")
      end, { desc = "NeoTree: Reveal diagnostics (bottom)" })
    end
  },
}
