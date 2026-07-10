-- driftwood — a flexible floating-window shell. It wraps a content *provider*
-- into a float you can move between five layouts. Its first (and, today, only)
-- provider is `symbols`: the LSP document-symbol outline.
--
-- Config is hierarchical: global keys describe the *window* (shared by every
-- provider); each `providers.<name>` table describes its *content* and may
-- override the global geometry. See docs/driftwood-design.md.

local M = {}

M.config = {
  -- ── global (window) ─────────────────────────────────────────────────────
  -- Per-layout sizing shared by every provider. width/height (and the max_*
  -- bounds) each accept:
  --   integer >= 1   → absolute cells
  --   float in (0,1) → fraction of the editor dimension
  --   "max"          → fill the axis (editor minus border/command-line)
  --   "fit"          → hug content, clamped by min_/max_ (re-fits on fold)
  -- A provider may override any of these under its own `layouts` table.
  layouts = {
    center = { width = "fit", height = "fit", min_width = 30, max_width = 60, max_height = 0.6 },
    left = { width = 30, height = "max" },
    right = { width = 30, height = "max" },
    top = { height = 15, width = "max" },
    bottom = { height = 15, width = "max" },
  },

  -- Normal-mode keys that move the active float between layouts at runtime.
  -- Wired in a later step; global-only (identical muscle memory everywhere).
  layout_keys = { left = "H", bottom = "J", top = "K", right = "L", center = "M" },

  border = "rounded",

  -- ── providers (content) ─────────────────────────────────────────────────
  providers = {
    symbols = {
      -- Normal-mode key that toggles this provider's float (also declared by
      -- the lazy spec's lazy-load trigger; keep the two in sync).
      key = ";",

      -- Layout the float opens in: "center" | "left" | "right" | "top" | "bottom".
      layout = "right",
      title = " Symbols ",

      -- How many levels to expand on open: a non-negative integer
      -- (0 = only top-level symbols, 1 = their direct children, …) or "all".
      initial_depth = "all",

      -- action -> key (string) or keys (list). Generic tree actions live in
      -- driftwood.ui; provider-specific actions (jump) in the provider.
      keys = {
        down = "j",
        up = "k",
        expand = "l",
        collapse = "h",
        jump = "<CR>",
        expand_all = "zR",
        collapse_all = "zM",
        close = { "q", ";" },
      },

      -- Optional per-provider geometry override, deep-merged over global layouts.
      -- layouts = { right = { width = 30 } },

      -- Per-layout content toggles read by the provider's render function. A
      -- layout absent here (right/left/top/bottom) renders the name only; the
      -- wider `center` layout also shows each symbol's line number.
      content = {
        center = { show_lnum = true },
      },

      chevron = { expanded = "▾", collapsed = "▸" },

      -- Live follow (preview) mode. As the cursor moves over the outline, paint
      -- the hovered symbol's full range in the origin window and move its cursor
      -- onto the symbol's name so the symbol is always visible on-screen.
      -- Browsing is non-destructive: dismissing with a close/toggle key snaps the
      -- origin cursor+view back to where it was on open — only `jump` commits.
      --   enabled  → on/off switch for the whole feature.
      --   hl       → highlight group painted (whole-line) over the symbol range.
      --   recenter → run `zz` in the origin window on each hover (else cursor only).
      follow = { enabled = true, hl = "Visual", recenter = true },

      -- Live symbol filter. A permanent bar on the float's top line advertises the
      -- trigger key; pressing it opens an editable prompt: type to filter and the
      -- outline narrows live to matches + their ancestor path, with the first match
      -- highlighted + previewed. Two query forms (parsed by the provider's matcher):
      --   "foo"          → name substring, smartcase.
      --   "@class"       → kind filter: the token after @ is a case-insensitive
      --                    prefix over SymbolKind names, unioned across every kind it
      --                    prefixes (@c → Class/Constructor/Constant, @fu → Function).
      --   "@function foo"→ both: Functions whose name also contains "foo".
      -- accept (<CR>)
      -- jumps to that first match; abandon (<Esc>) hands the *real* cursor to the
      -- narrowed tree so j/k/l/h and <CR> browse it exactly like the full outline.
      -- A second <Esc> (normal mode) clears the filter and restores the full tree
      -- (folds intact — filtering never mutates them). `/` again refines the query.
      --   enabled → on/off switch for the whole feature.
      --   key     → normal-mode key (inside the float) that opens the prompt. The
      --             provider's kind sigil (@) also opens it, pre-seeded into kind mode.
      --   hint    → text shown in the bar when idle (advertises the feature).
      --   prompt  → glyph drawn (as inline virtual text) before the live query.
      --   keys    → prompt (insert-mode) keys: accept jumps to the first match,
      --             abandon hands off to normal-mode browsing. Key or list of keys.
      search = {
        enabled = true,
        key = "/",
        hint = "/ name  @kind",
        prompt = "/ ",
        placeholder = "(no matches)",
        keys = {
          accept = "<CR>",
          abandon = "<Esc>",
        },
        -- Filter highlights. match = matched substring, context = dimmed ancestor
        -- rows, selection = the first-match row highlighted while typing,
        -- hint/prompt/query = the bar, placeholder = the "(no matches)" line.
        hl = {
          prompt = "Comment",
          hint = "Comment",
          query = "Normal",
          match = "Search",
          context = "Comment",
          selection = "Visual",
          placeholder = "Comment",
        },
      },

      -- Pinned symbols. Press `key` on a row to pin/unpin it; pinned symbols carry
      -- a right-aligned number badge, are numbered by document order (top→bottom),
      -- stay visible even inside a collapsed parent, and are jumped to with the
      -- `jump_keys` (1..9) while the float is open. Pins persist on disk (keyed by
      -- name+kind+ancestor-path) and are pruned when a symbol no longer matches.
      --   enabled   → on/off switch for the whole feature.
      --   key       → normal-mode key (inside the float) that toggles the row's pin.
      --   jump_keys → keys that jump to pin N (also shadow vim counts in the float).
      --   hl        → highlight group for the number badge.
      pins = {
        enabled = true,
        key = "p",
        jump_keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9" },
        hl = "Number",
      },

      -- Non-kind highlights. Kind highlights are in `kind_hl` below.
      hl = { chevron = "Comment", name = "Normal", lnum = "Comment" },

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

      -- SymbolKind (LSP numeric) -> highlight group. Linked to classic groups
      -- your colorscheme defines, so the outline follows the active theme.
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
    },
  },
}

-- Flatten the hierarchical config for one provider into the resolved shape the
-- ui/window/provider modules consume: global geometry deep-merged with the
-- provider's overrides, everything else taken from the provider.
local function resolve_config(global, pcfg)
  return {
    initial_depth = pcfg.initial_depth,
    keys = pcfg.keys,
    follow = pcfg.follow,
    search = pcfg.search,
    pins = pcfg.pins,
    chevron = pcfg.chevron,
    hl = pcfg.hl,
    icons = pcfg.icons,
    kind_hl = pcfg.kind_hl,
    content = pcfg.content,
    layout_keys = global.layout_keys,
    window = {
      layout = pcfg.layout,
      border = global.border,
      title = pcfg.title,
      layouts = vim.tbl_deep_extend("force", {}, global.layouts, pcfg.layouts or {}),
    },
  }
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  for name, pcfg in pairs(M.config.providers) do
    if pcfg.key then
      vim.keymap.set("n", pcfg.key, function()
        M.toggle(name)
      end, { desc = "Toggle driftwood: " .. name })
    end
  end
end

function M.toggle(name)
  name = name or "symbols"
  local ui = require("driftwood.ui")
  if ui.is_open() then
    ui.close(true)
    return
  end

  local pcfg = M.config.providers[name]
  if not pcfg then
    vim.notify("driftwood: no provider named '" .. name .. "'", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local origin = {
    win = vim.api.nvim_get_current_win(),
    pos = vim.api.nvim_win_get_cursor(0),
  }

  local provider = require("driftwood.providers." .. name)
  local cfg = resolve_config(M.config, pcfg)
  provider.fetch(bufnr, function(roots)
    if not roots then
      vim.notify("driftwood: no document symbols", vim.log.levels.INFO)
      return
    end
    ui.open(provider, roots, cfg, origin)
  end)
end

return M
