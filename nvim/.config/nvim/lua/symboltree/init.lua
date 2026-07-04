-- symboltree — LSP document-symbol outline in a floating window.
-- Public API + config. Everything here is the flexibility surface: rebind any
-- key, swap any glyph/highlight, or move the window without touching core code.

local M = {}

M.config = {
  -- Normal-mode key that toggles the float (also bound by the lazy spec's
  -- lazy-load trigger; keep the two in sync if you change it).
  keymap = ";",

  -- How many levels to expand when the float opens: a non-negative integer
  -- (0 = only top-level symbols, 1 = their direct children, …) or "all".
  initial_depth = "all",

  -- action -> key (string) or keys (list). Actions live in symboltree.ui.
  keys = {
    down = "j",
    up = "k",
    expand = "l",
    collapse = "h",
    jump = "<CR>",
    expand_all = "zR",
    collapse_all = "zM",
    close = { "q", "<Esc>", ";" },
  },

  window = {
    -- Active layout: "center" | "left" | "right" | "top" | "bottom",
    -- or a function(ctx) -> { relative, row, col, width, height, anchor? }
    -- where ctx = { columns, lines, avail_w, avail_h, content_w, content_h }.
    layout = "right",
    border = "rounded",
    title = " Symbols ",

    -- Per-layout sizing. width/height (and the max_* bounds) each accept:
    --   integer >= 1   → absolute cells
    --   float in (0,1) → fraction of the editor dimension
    --   "max"          → fill the axis (editor minus border/command-line)
    --   "fit"          → hug content, clamped by min_/max_ (re-fits on fold)
    -- Docked layouts sit flush against their edge and are centered on the free
    -- axis; a maximized dimension spans the full editor.
    layouts = {
      center = { width = "fit", height = "fit", min_width = 30, max_width = 60, max_height = 0.6 },
      left = { width = 30, height = "max" },
      right = { width = 30, height = "max" },
      top = { height = 15, width = "max" },
      bottom = { height = 15, width = "max" },
    },
  },

  chevron = { expanded = "▾", collapsed = "▸" },

  -- Non-kind highlights. Kind highlights are in `kind_hl` below.
  hl = { chevron = "Comment", name = "Normal" },

  -- SymbolKind (LSP numeric) -> nerd-font glyph.
  icons = {
    [1] = "", -- File
    [2] = "󰆧", -- Module
    [3] = "", -- Namespace
    [4] = "", -- Package
    [5] = "󰠱", -- Class
    [6] = "󰆧", -- Method
    [7] = "", -- Property
    [8] = "󰜢", -- Field
    [9] = "", -- Constructor
    [10] = "", -- Enum
    [11] = "", -- Interface
    [12] = "󰊕", -- Function
    [13] = "󰀫", -- Variable
    [14] = "󰏿", -- Constant
    [15] = "", -- String
    [16] = "󰎠", -- Number
    [17] = "", -- Boolean
    [18] = "󰅪", -- Array
    [19] = "", -- Object
    [20] = "󰌋", -- Key
    [21] = "󰟢", -- Null
    [22] = "", -- EnumMember
    [23] = "󰙅", -- Struct
    [24] = "", -- Event
    [25] = "󰆕", -- Operator
    [26] = "", -- TypeParameter
    default = "",
  },

  -- SymbolKind (LSP numeric) -> highlight group. Linked to classic groups your
  -- colorscheme already defines, so the outline follows the active theme.
  kind_hl = {
    [1] = "Normal", -- File
    [2] = "Include", -- Module
    [3] = "Include", -- Namespace
    [4] = "Include", -- Package
    [5] = "Type", -- Class
    [6] = "Function", -- Method
    [7] = "Identifier", -- Property
    [8] = "Identifier", -- Field
    [9] = "Function", -- Constructor
    [10] = "Type", -- Enum
    [11] = "Type", -- Interface
    [12] = "Function", -- Function
    [13] = "Identifier", -- Variable
    [14] = "Constant", -- Constant
    [15] = "String", -- String
    [16] = "Number", -- Number
    [17] = "Boolean", -- Boolean
    [18] = "Type", -- Array
    [19] = "Type", -- Object
    [20] = "Identifier", -- Key
    [21] = "Constant", -- Null
    [22] = "Constant", -- EnumMember
    [23] = "Type", -- Struct
    [24] = "Identifier", -- Event
    [25] = "Operator", -- Operator
    [26] = "Type", -- TypeParameter
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  vim.keymap.set("n", M.config.keymap, M.toggle, { desc = "Toggle symbol tree" })
end

function M.toggle()
  local ui = require("symboltree.ui")
  if ui.is_open() then
    ui.close(true)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local origin = {
    win = vim.api.nvim_get_current_win(),
    pos = vim.api.nvim_win_get_cursor(0),
  }

  require("symboltree.lsp").request(bufnr, function(roots)
    if not roots then
      vim.notify("symboltree: no document symbols", vim.log.levels.INFO)
      return
    end
    ui.open(roots, M.config, origin)
  end)
end

return M
