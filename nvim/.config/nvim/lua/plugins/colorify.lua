return {
  dir = vim.fn.stdpath("config") .. "/lua/colorify",
  config = function()
    require("colorify").run()
  end
}
