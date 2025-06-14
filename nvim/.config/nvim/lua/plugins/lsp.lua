return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end
  },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "pyright" },
      })
    end
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")

      -- -- Set a custom border for the hover window
      -- -- local border = {
      -- --   { "╭", "FloatBorder" },
      -- --   { "─", "FloatBorder" },
      -- --   { "╮", "FloatBorder" },
      -- --   { "│", "FloatBorder" },
      -- --   { "╯", "FloatBorder" },
      -- --   { "─", "FloatBorder" },
      -- --   { "╰", "FloatBorder" },
      -- --   { "│", "FloatBorder" },
      -- -- }
      --
      -- -- Specify how the border looks like
      -- local border = {
      --     { '┌', 'FloatBorder' },
      --     { '─', 'FloatBorder' },
      --     { '┐', 'FloatBorder' },
      --     { '│', 'FloatBorder' },
      --     { '┘', 'FloatBorder' },
      --     { '─', 'FloatBorder' },
      --     { '└', 'FloatBorder' },
      --     { '│', 'FloatBorder' },
      -- }
      --
      -- -- Add the border on hover and on signature help popup window
      -- local handlers = {
      --     ['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, { border = border }),
      --     ['textDocument/signatureHelp'] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = border }),
      -- }
      --
      -- -- Add border to the diagnostic popup window
      -- vim.diagnostic.config({
      --     virtual_text = {
      --         prefix = '■ ', -- Could be '●', '▎', 'x', '■', , 
      --     },
      --     float = { border = border },
      -- })



      -- Automatically configure installed servers
      require("mason-lspconfig").setup_handlers({
        function(server_name)
          lspconfig[server_name].setup({ handlers = handlers })
        end,
      })

    end
  }
}
