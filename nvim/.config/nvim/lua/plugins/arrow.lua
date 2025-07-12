return {
  "otavioschwanck/arrow.nvim",
  dependencies = {
    { "nvim-tree/nvim-web-devicons" },
  },
  opts = {
    show_icons = true,
    leader_key = ',',            -- Recommended to be a single key
    buffer_leader_key = 'm',     -- Per Buffer Mappings
    hide_handbook = true,        -- set to true to hide the shortcuts on menu.
    hide_buffer_handbook = true, --set to true to hide shortcuts on buffer menu
    mappings = {
      edit = "e",
      delete_mode = "d",
      clear_all_items = "C",
      toggle = "s", -- used as save if separate_save_and_remove is true
      open_vertical = "v",
      open_horizontal = "h",
      quit = "q",
      remove = "x", -- only used if separate_save_and_remove is true
      next_item = "]",
      prev_item = "["
    },
  }
}
