local wezterm = require("wezterm")
local act = wezterm.action
local M = {}

function M.setup(config)
  -- Disable defaults ON PURPOSE
  config.disable_default_key_bindings = false

  -- Restore useful defaults explicitly
  config.hyperlink_rules = wezterm.default_hyperlink_rules()

  -- Mouse
  config.mouse_bindings = {
    {
      event = { Up = { streak = 1, button = "Left" } },
      mods = "CTRL",
      action = act.OpenLinkAtMouseCursor,
    },
  }

  -- leader
  -- config.leader = {
  --   key = "w",
  --   mods = "CTRL",
  --   timeout_milliseconds = 1000,
  -- }

  config.keys = {
    {
      key = 'w',
      mods = 'CTRL',
      action = act.ActivateKeyTable {
        name = 'leader_mode',
        one_shot = false,
      },
    },
    {
      key = "c",
      mods = "SUPER",
      action = act.CopyTo("Clipboard"),
    },
    {
      key = 'y',
      mods = 'CTRL|SHIFT',
      action = act.SwitchToWorkspace {
        name = 'default',
      },
    },
    -- Switch to a monitoring workspace, which will have `top` launched into it
    {
      key = 'u',
      mods = 'CTRL|SHIFT',
      action = act.SwitchToWorkspace {
        name = 'monitoring',
        spawn = {
          args = { 'top' },
        },
      },
    },
    {
      key = '9',
      mods = 'ALT',
      action = act.ShowLauncherArgs {
        flags = 'FUZZY|WORKSPACES',
      },
    },

    { key = 'F9', mods = 'ALT', action = wezterm.action.ShowTabNavigator },
  }

  config.key_tables = {
    leader_mode = {
      -- =====================
      -- Exit
      -- =====================
      { key = 'Escape',   action = act.PopKeyTable },

      -- =====================
      -- Pane navigation (vim-like)
      -- =====================
      { key = 'h',        action = act.ActivatePaneDirection 'Left' },
      { key = 'j',        action = act.ActivatePaneDirection 'Down' },
      { key = 'k',        action = act.ActivatePaneDirection 'Up' },
      { key = 'l',        action = act.ActivatePaneDirection 'Right' },

      -- =====================
      -- Core
      -- =====================
      { key = 'p',        action = act.ActivateCommandPalette },
      { key = 'y',        action = act.ActivateCopyMode },
      { key = 'u',        action = act.EmitEvent 'update-plugins' },
      { key = 'm',        action = act.TogglePaneZoomState },

      -- =====================
      -- Tabs
      -- =====================
      { key = 't',        action = act.SpawnTab 'CurrentPaneDomain' },
      { key = 'x',        action = act.CloseCurrentTab { confirm = false } },
      { key = '[',        action = act.ActivateTabRelative(-1) },
      { key = ']',        action = act.ActivateTabRelative(1) },
      { key = 'PageUp',   action = act.MoveTabRelative(1) },
      { key = 'PageDown', action = act.MoveTabRelative(-1) },

      -- =====================
      -- Panes
      -- =====================
      { key = 'v',        action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
      { key = 's',        action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
      { key = 'w',        action = act.CloseCurrentPane { confirm = false } },

      -- =====================
      -- Resize panes
      -- =====================
      { key = 'H',        action = act.AdjustPaneSize { 'Left', 3 } },
      { key = 'J',        action = act.AdjustPaneSize { 'Down', 3 } },
      { key = 'K',        action = act.AdjustPaneSize { 'Up', 3 } },
      { key = 'L',        action = act.AdjustPaneSize { 'Right', 3 } },
    },
  }
end

return M
