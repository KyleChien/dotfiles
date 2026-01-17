local wezterm = require('wezterm')
local tabline = wezterm.plugin.require(
  "https://github.com/michaelbrusegard/tabline.wez"
)
local M = {}

function M.setup(config)
  tabline.setup({
    options = {
      tabs_enabled = true,
      icons_enabled = false,
      section_separators = "",
      component_separators = "",
      tab_separators = "",
      theme_overrides = {
        -- Defining colors for a new key table
        leader_mode = {
          a = { fg = '#181825', bg = '#cba6f7' },
          b = { fg = '#cba6f7', bg = '#313244' },
          c = { fg = '#cdd6f4', bg = '#181825' },
        },
        tab = {
          active = { fg = '#ffffff', bg = '#313244' },
          inactive = { fg = '#7F849C', bg = '#313244' },
          inactive_hover = { fg = '#f5c2e7', bg = '#313244' },
        }
      },
    },
    sections = {
      tabline_a = { "mode" },
      tabline_b = {},
      tabline_c = {},
      tab_active = {
        " • ",
        { "process", padding = 0 },
      },
      tab_inactive = {
        " • ",
        { "process", padding = 0 },
      },
      tabline_x = {},
      tabline_y = { "workspace" },
      tabline_z = { "domain" },
    },
  })
end

return M
