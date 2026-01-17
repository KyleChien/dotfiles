local wezterm = require("wezterm")

-- =========================
-- Events
-- =========================

wezterm.on("update-plugins", function(window, pane)
  wezterm.plugin.update_all()
  window:toast_notification("wezterm", "Plugins updated!", nil, 4000)
end)

wezterm.on("toggle-opacity", function(window, pane)
  local overrides = window:get_config_overrides() or {}
  overrides.window_background_opacity =
    overrides.window_background_opacity and nil or 1
  window:set_config_overrides(overrides)
end)

-- =========================
-- Base config
-- =========================
local config = wezterm.config_builder()
config.color_scheme = "rose-pine-moon"
config.font_size = 18
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.9
config.macos_window_background_blur = 10
config.inactive_pane_hsb = {
  saturation = 0.5,
  brightness = 0.5,
}

-- =========================
-- Load keybindings module
-- =========================
require("keys").setup(config)

-- =========================
-- Smart-splits plugin
-- =========================
require("plugins.smart-splits").setup(config)

-- =========================
-- Tabline plugin
-- =========================
require("plugins.tabline").setup({})

return config

