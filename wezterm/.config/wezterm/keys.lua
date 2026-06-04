local wezterm = require("wezterm")
local act = wezterm.action
local M = {}

function M.setup(config)
  -- Disable defaults ON PURPOSE
  config.disable_default_key_bindings = true

  -- Restore useful defaults explicitly
  config.hyperlink_rules = wezterm.default_hyperlink_rules()

  -- Mouse
  config.mouse_bindings = {
    {
      event = { Up = { streak = 7, button = "Left" } },
      mods = "CTRL",
      action = act.OpenLinkAtMouseCursor,
    },
  }

  config.keys = {
    --- Copy to clipboard
    { key = 'c', mods = 'CMD', action = act.CopyTo 'Clipboard' },
    -- Paste from clipboard
    { key = 'v', mods = 'CMD', action = act.PasteFrom 'Clipboard' },
    -- Quit wezterm
    { key = 'q', mods = 'CMD', action = act.QuitApplication },

    -- =================================== mode ====================================
    {
      key = "w",
      mods = "CTRL",
      action = act.ActivateKeyTable {
        name = 'leader',
        one_shot = true,
      },
    },
    {
      key = 'w',
      mods = 'CTRL|SHIFT',
      action = act.ActivateKeyTable {
        name = 'leader',
        one_shot = false,
      },
    },
    {
      key = 'v',
      mods = "CTRL|SHIFT",
      action = act.ActivateCopyMode
    },

    -- ================================= workspace =================================
    {
      key = 'h',
      mods = 'CTRL|SHIFT',
      action = act.SwitchToWorkspace {
        name = 'west',
      },
    },
    {
      key = 'j',
      mods = 'CTRL|SHIFT',
      action = act.SwitchToWorkspace {
        name = 'north',
      },
    },
    {
      key = 'k',
      mods = 'CTRL|SHIFT',
      action = act.SwitchToWorkspace {
        name = 'south',
      },
    },
    {
      key = 'l',
      mods = 'CTRL|SHIFT',
      action = act.SwitchToWorkspace {
        name = 'east',
      },
    },
    {
      key = '9',
      mods = 'ALT',
      action = act.ShowLauncherArgs {
        flags = 'FUZZY|WORKSPACES',
      },
    },
    {
      key = 'F9',
      mods = 'ALT',
      action = wezterm.action.ShowTabNavigator
    },

    -- ================================= swap pane =================================
    { key = 'h', mods = 'ALT|SHIFT', action = act.RotatePanes 'CounterClockwise', },
    { key = 'l', mods = 'ALT|SHIFT', action = act.RotatePanes 'Clockwise' },
    {
      key = 'j',
      mods = 'ALT|SHIFT',
      action = act.PaneSelect {
        alphabet = '1234567890',
        mode = 'SwapWithActive',
      },
    },
    {
      key = 'k',
      mods = 'ALT|SHIFT',
      action = act.PaneSelect {
        alphabet = '1234567890',
        mode = 'SwapWithActive',
      },
    },
  }

  config.key_tables = {
    leader = {
      { key = 'Escape', action = act.PopKeyTable },
      { key = 'p',      action = act.ActivateCommandPalette },
      { key = 'm',      action = act.TogglePaneZoomState },

      -- ==================================== tab ====================================
      { key = 't',      action = act.SpawnTab 'CurrentPaneDomain' },
      { key = 'w',      action = act.CloseCurrentTab { confirm = true } },
      { key = 'h',      action = act.ActivateTabRelative(5) },
      { key = 'l',      action = act.ActivateTabRelative(7) },
      { key = 'H',      action = act.MoveTabRelative(5) },
      { key = 'L',      action = act.MoveTabRelative(7) },

      -- =================================== pane ====================================
      { key = '-',      action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
      { key = '|',      action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
      { key = 'x',      action = act.CloseCurrentPane { confirm = false } },

    },
  }

  -- ==================================== tab ====================================
  for i = 1, 9 do
    -- leader + number to activate that tab
    table.insert(config.key_tables.leader, {
      key = tostring(i),
      action = act.ActivateTab(i - 1),
    })
  end
end

return M
