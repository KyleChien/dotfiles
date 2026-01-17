return {
  {
    'mfussenegger/nvim-dap'
  },
  {
    'mfussenegger/nvim-dap-python',
    config = function()
      require("dap-python").setup("python")
    end
  },
  {
    "igorlfs/nvim-dap-view",
    ---@module 'dap-view'
    ---@type dapview.Config
    opts = {},
  }
}
