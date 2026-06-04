local wezterm = require("wezterm")
local F = require("functions")
local nerdfonts = wezterm.nerdfonts
local colors = {
	bg        = "#303446", -- Catppuccin Frappe
	fg        = "#ffffff", -- text in segments and active tab
	surface   = "#414559", -- text-zone inset (Catppuccin Frappe Surface 0)
	icon      = "#303446", -- icon foreground (cutout effect on accent bg)
	normal    = "#b4d4cf", -- vague builtin   → normal mode
	leader    = "#d8647e", -- vague error     → leader mode
	keytable  = "#f3be7c", -- vague warning   → key-table mode / cwd segment
	workspace = "#6e94b2", -- vague keyword   → workspace segment
	dim       = "#606079", -- vague comment   → inactive tab text
}
local config = wezterm.config_builder()

-- ============================================================================
-- Color scheme / workspace defaults
-- ============================================================================
config.default_workspace = "west"
config.color_scheme = "rose-pine-moon"
config.font_size = 18

-- ============================================================================
-- Window: opacity, blur, decorations, and pane dimming
-- ============================================================================
config.window_decorations = "RESIZE"
config.window_background_opacity = 1.0
config.macos_window_background_blur = 10
config.inactive_pane_hsb = {
	saturation = 0.5,
	brightness = 0.5,
}

-- ============================================================================
-- Tab bar: appearance and behavior of the tab line
-- ============================================================================
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = true
config.status_update_interval = 1000
config.tab_bar_at_bottom = false
config.tab_max_width = 30
config.use_fancy_tab_bar = false

-- ============================================================================
-- Keybindings
-- ============================================================================
require("keys").setup(config)

-- ============================================================================
-- Plugins
-- ============================================================================
require("plugins.smart-splits").setup(config)
-- require("plugins.tabline").setup()

-- ============================================================================
-- Event: update-plugins
-- ============================================================================
wezterm.on("update-plugins", function(window, pane)
	wezterm.plugin.update_all()
	window:toast_notification("wezterm", "Plugins updated!", nil, 4000)
end)

-- ============================================================================
-- Event: toggle-opacity
-- Toggles window background opacity between the configured value and fully opaque.
-- ============================================================================
wezterm.on("toggle-opacity", function(window, pane)
	local overrides = window:get_config_overrides() or {}
	overrides.window_background_opacity = overrides.window_background_opacity and nil or 1
	window:set_config_overrides(overrides)
end)

-- ============================================================================
-- Event: update-status
-- Builds the left status (workspace / active key-table / leader indicator) and
-- the right status (cwd, username, hostname, clock) on every refresh tick.
-- ============================================================================

wezterm.on("update-status", function(window, pane)
	-- Mode: key-table name, "leader", or "normal"
	local active_key_table = window:active_key_table()
	local mode, mode_color
	if active_key_table then
		mode = active_key_table
		mode_color = colors.keytable
	elseif window:leader_is_active() then
		mode = "leader"
		mode_color = colors.leader
	else
		mode = "normal"
		mode_color = colors.normal
	end

	local workspace = window:active_workspace()

	-- Resolve and truncate the current working directory for display
	local cwd = pane:get_current_working_dir()
	if cwd then
		if type(cwd) == "userdata" then
			cwd = F.truncate_path(cwd.path, config.tab_max_width)
		end
	else
		cwd = ""
	end

	-- Left status: mode segment then workspace segment
	window:set_left_status(wezterm.format({
		{ Attribute = { Intensity = "Bold" } },
		-- Mode segment
		{ Background = { Color = colors.bg } },
		{ Foreground = { Color = mode_color } },
		{ Text = nerdfonts.ple_left_half_circle_thick },
		{ Background = { Color = mode_color } },
		{ Foreground = { Color = colors.icon } },
		{ Text = nerdfonts.oct_north_star .. " " },
		{ Background = { Color = colors.surface } },
		{ Foreground = { Color = mode_color } },
		{ Text = " " .. mode:upper() .. " " },
		{ Background = { Color = colors.bg } },
		{ Foreground = { Color = colors.surface } },
		{ Text = nerdfonts.ple_right_half_circle_thick },
		{ Text = " " },
	}))

	-- Right status: cwd, username, hostname and clock as powerline segments
	window:set_right_status(wezterm.format({
		-- Wezterm has a built-in nerd fonts
		-- https://wezfurlong.org/wezterm/config/lua/wezterm/nerdfonts.html

		-- cwd segment
		{ Text = " " },
		{ Background = { Color = colors.bg } },
		{ Foreground = { Color = colors.keytable } },
		{ Text = nerdfonts.ple_left_half_circle_thick },
		{ Background = { Color = colors.keytable } },
		{ Foreground = { Color = colors.icon } },
		{ Text = nerdfonts.cod_folder_opened .. " " },
		{ Background = { Color = colors.surface } },
		{ Foreground = { Color = colors.fg } },
		{ Text = " " .. cwd .. " " },
		{ Background = { Color = colors.bg } },
		{ Foreground = { Color = colors.surface } },
		{ Text = nerdfonts.ple_right_half_circle_thick },

		-- Workspace segment
		{ Text = " " },
		{ Background = { Color = colors.bg } },
		{ Foreground = { Color = colors.workspace } },
		{ Text = nerdfonts.ple_left_half_circle_thick },
		{ Background = { Color = colors.workspace } },
		{ Foreground = { Color = colors.icon } },
		{ Text = nerdfonts.oct_package .. " " },
		{ Background = { Color = colors.surface } },
		{ Foreground = { Color = colors.fg } },
		{ Text = " " .. workspace .. " " },
		{ Background = { Color = colors.bg } },
		{ Foreground = { Color = colors.surface } },
		{ Text = nerdfonts.ple_right_half_circle_thick }

		-- -- username segment
		-- { Text       = " "                                   },
		-- { Background = { Color = colors.bg }         },
		-- { Foreground = { Color = colors.ansi[6] }            },
		-- { Text       = nerdfonts.ple_left_half_circle_thick  },
		-- { Background = { Color = colors.ansi[6] }            },
		-- { Foreground = { Color = colors.bg }         },
		-- { Text       = nerdfonts.fa_user .. " "              },
		-- { Background = { Color = colors.icon }            },
		-- { Foreground = { Color = colors.surface }         },
		-- { Text       = " " .. custom.username               },
		-- { Background = { Color = colors.bg }         },
		-- { Foreground = { Color = colors.icon }            },
		-- { Text       = nerdfonts.ple_right_half_circle_thick },

		-- -- hostname segment
		-- { Text       = " "                                   },
		-- { Background = { Color = colors.bg }         },
		-- { Foreground = { Color = colors.ansi[7] }            },
		-- { Text       = nerdfonts.ple_left_half_circle_thick  },
		-- { Background = { Color = colors.ansi[7] }            },
		-- { Foreground = { Color = colors.icon }            },
		-- { Text       = nerdfonts.cod_server .. " "           },
		-- { Background = { Color = colors.icon }            },
		-- { Foreground = { Color = colors.surface }         },
		-- { Text       = " " .. custom.hostname.current        },
		-- { Background = { Color = colors.bg }         },
		-- { Foreground = { Color = colors.icon }            },
		-- { Text       = nerdfonts.ple_right_half_circle_thick },

		-- -- clock segment
		-- { Text       = " "                                   },
		-- { Background = { Color = colors.bg }         },
		-- { Foreground = { Color = colors.dim }            },
		-- { Text       = nerdfonts.ple_left_half_circle_thick  },
		-- { Background = { Color = colors.dim }            },
		-- { Foreground = { Color = colors.bg }         },
		-- { Text       = nerdfonts.md_calendar_clock .. " "    },
		-- { Background = { Color = colors.icon }            },
		-- { Foreground = { Color = colors.surface }         },
		-- { Text       = " " .. time                           },
		-- { Background = { Color = colors.bg }         },
		-- { Foreground = { Color = colors.icon }            },
		-- { Text       = nerdfonts.ple_right_half_circle_thick },
	}))
end)

-- ============================================================================
-- Event: format-tab-title
-- Renders each tab as "N icon title", centered within the tab cell.
-- Active tabs are bold + accent color; inactive tabs are dimmed.
-- Icons are prefixed for context (docker, k8s, ssh, top, vim, watch) and
-- pane state (zoomed, copy mode, unseen output).
-- ============================================================================
wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover)
	local id = tostring(tab.tab_index + 1)
	local bg, fg
	if tab.is_active then
		bg, fg = colors.fg, colors.bg
	elseif hover then
		bg, fg = colors.dim, "#ffffff"
	else
		bg, fg = colors.surface, "#ffffff"
	end
	return {
		{ Background = { Color = bg } },
		{ Foreground = { Color = fg } },
		{ Text = " " .. id .. " " },
	}
end)

-- ============================================================================
-- Return the assembled config object to wezterm
-- ============================================================================
return config
