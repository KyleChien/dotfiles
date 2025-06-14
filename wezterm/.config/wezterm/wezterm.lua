-- local wezterm = require("wezterm")
-- local keys = require("keys")
--
-- -- This will hold the configuration.
-- local config = wezterm.config_builder()
--
-- keys.setup(config)
-- return config

local wezterm = require("wezterm")

local config = wezterm.config_builder()
config.keys = config.keys or {}
config.key_tables = config.key_tables or {}
config.color_scheme = "rose-pine-moon"
config.font_size = 20
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.9
config.macos_window_background_blur = 10
config.leader = { key = "w", mods = "CTRL" }

-- tabline
local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")
tabline.setup({
	options = {
		tabs_enabled = true,
		section_separators = "",
		component_separators = "",
		tab_separators = "",
	},
	sections = {
		tabline_a = { "mode" },
		tabline_b = { "" },
		tabline_c = { "" },
		tab_active = {
			"index",
			{ "process", padding = { left = 0, right = 1 } },
			{ "zoomed", padding = 0 },
		},
		tab_inactive = { "index", { "process", padding = { left = 0, right = 1 } } },
		tabline_x = { "" },
		tabline_y = { "workspace" },
		tabline_z = { "domain" },
	},
	extensions = {},
})

-- local act = wezterm.action
-- local pane_resize = 5
-- local keys = {
-- 	-- Navigation
-- 	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
-- 	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
-- 	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
-- 	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
--
-- 	-- Resizing Panes
-- 	{ key = "H", mods = "LEADER", action = act.AdjustPaneSize({ "Left", pane_resize }) },
-- 	{ key = "J", mods = "LEADER", action = act.AdjustPaneSize({ "Down", pane_resize }) },
-- 	{ key = "K", mods = "LEADER", action = act.AdjustPaneSize({ "Up", pane_resize }) },
-- 	{ key = "L", mods = "LEADER", action = act.AdjustPaneSize({ "Right", pane_resize }) },
--
-- 	-- Splitting Panes
-- 	{ key = "v", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
-- 	{ key = "h", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
--
-- 	-- Swapping Windows
-- 	{ key = "<", mods = "LEADER", action = act.MoveTabRelative(-1) },
-- 	{ key = ">", mods = "LEADER", action = act.MoveTabRelative(1) },
-- }
--
-- for _, key in ipairs(keys) do
-- 	table.insert(config.keys, key)
-- end
--
-- -- Define key table for resizing
-- config.key_tables.resize_pane = {
-- 	{ key = "h", mods = "SHIFT", action = act.AdjustPaneSize({ "Left", pane_resize }) },
-- 	{ key = "j", mods = "SHIFT", action = act.AdjustPaneSize({ "Down", pane_resize }) },
-- 	{ key = "k", mods = "SHIFT", action = act.AdjustPaneSize({ "Up", pane_resize }) },
-- 	{ key = "l", mods = "SHIFT", action = act.AdjustPaneSize({ "Right", pane_resize }) },
-- 	{ key = "Escape", action = act.PopKeyTable },
-- }

return config
