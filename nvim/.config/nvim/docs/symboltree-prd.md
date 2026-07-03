# PRD — `symboltree`: LSP document-symbol outline in a floating window

## Problem Statement

When I'm editing a large source file, I lose the shape of it. To jump to a
particular function, class, or method I either scroll, `/`-search by name, or
reach for a heavier picker/UI. My previous approach (dropbar's `pick` on `;`)
is now disabled, and I want a lighter, purpose-built way to see the whole
document's structure at a glance and navigate straight to any symbol —
without leaving the keyboard or losing my place if I decide not to jump.

## Solution

A small, self-contained Neovim plugin, `symboltree`, that on a single keypress
(`;`) pops up a **centered floating window** containing the current buffer's
**document-symbol tree** (from the LSP), fully expanded, with the cursor
pre-positioned on the symbol that encloses my current line. Inside the float I
navigate the tree entirely with `h`/`j`/`k`/`l` (the fold model I already use
in nvim-tree): sweep rows with `j`/`k`, expand/collapse branches with `l`/`h`,
and press `<CR>` to jump to a symbol and close. If I change my mind, `q`,
`<Esc>`, or `;` again closes the float and returns me exactly where I was.

The plugin is intentionally small and modular, dependency-free (no icon or UI
libraries required), and every key and behavior is rebindable through a config
table so it can be extended later without touching the core.

## User Stories

1. As a developer editing a long file, I want to press one key (`;`) to see the whole file's symbol outline, so that I can grasp its structure without scrolling.
2. As a developer, I want the outline to appear in a floating window that takes focus, so that I can navigate it immediately without a window-switch step.
3. As a developer, I want the tree to open **fully expanded**, so that the entire outline is scannable the instant it appears.
4. As a developer, I want the cursor to land on the symbol that **encloses my current line** when the float opens, so that I'm oriented instantly and often one keypress from my destination.
5. As an nvim-tree user, I want `j`/`k` to move down/up across **every visible row** regardless of depth, so that navigation matches muscle memory I already have.
6. As a developer, I want `l` to **expand** a collapsed branch, so that I can reveal a symbol's children on demand.
7. As a developer, I want `l` on a **leaf** node to do nothing (no jump), so that "go in" is unambiguous and I never jump by accident while exploring.
8. As a developer, I want `h` to **collapse** an expanded branch, so that I can hide noise I don't care about.
9. As a developer, I want `h` on an **already-collapsed node or a leaf** to hop to its **parent**, so that I can climb the tree quickly with the same key.
10. As a developer, I want `<CR>` to **jump to the symbol under the cursor and close** the float, so that selecting is a single, decisive action.
11. As a developer, I want jumps to land on the symbol's **name identifier** (`selectionRange.start`), so that I arrive on the name rather than a leading comment or decorator.
12. As a developer, I want `zR` to **expand all** and `zM` to **collapse all**, so that I can flip between a bird's-eye and a detailed view instantly.
13. As a developer, I want `;`, `q`, and `<Esc>` to **close** the float, so that dismissing it is frictionless with familiar keys.
14. As a developer, I want closing the float (without jumping) to **restore my original window and cursor**, so that peeking at the outline never costs me my place.
15. As a developer, I want the outline generated from the **live LSP state** each time I open it, so that I never see a stale tree after edits.
16. As a developer working in files whose server returns a **flat** symbol list (`SymbolInformation[]`), I want the plugin to still show a usable flat outline, so that it works regardless of server capabilities.
17. As a developer working in files whose server returns a **nested** symbol list (`DocumentSymbol[]`), I want the full hierarchy with expand/collapse, so that I get real tree navigation where it's available.
18. As a developer with **multiple LSP clients** attached (e.g. server + linter), I want symbols merged from all capable clients, so that I don't miss part of the outline.
19. As a developer, I want a brief **notification and no empty window** when there are no symbols or no capable client, so that I get clear feedback instead of a blank float.
20. As a developer, I want each symbol prefixed with a **kind icon** (function, class, method, …) highlighted by kind, so that I can distinguish symbol types at a glance.
21. As a developer, I want kind highlights **linked to my colorscheme's groups**, so that the outline matches whatever theme I'm using without manual color config.
22. As a developer, I want a **chevron on branch nodes** (and nothing on leaves), so that I can see at a glance what's foldable.
23. As a developer with a huge file, I want the float to **clamp its size and scroll internally**, so that a massive outline stays usable and on-screen.
24. As a developer, I want the float to open as a **right-hand column with maximized height** by default, with a rounded border and ` Symbols ` title, so that the outline docks where I expect and stays out of my editing area.
25. As a power user, I want to choose the float's **layout** from `center` / `left` / `right` / `top` / `bottom` (or a function), so that I can dock the outline where I like without patching the plugin.
30. As a power user, I want each layout's **width and height independently sizable** — absolute cells, a fraction of the editor, `"max"`, or `"fit"` — so that I can dial in exactly the panel shape I want per layout.
31. As a power user, I want a **maximized** dimension to fill the editor edge-to-edge without clipping the border or crowding the command line, so that a docked panel looks intentional.
32. As a developer, I want the float to **always stay floating** (never a split), so that it never disturbs my window layout.
26. As a power user, I want to **rebind any key and swap any action** through a config table, so that I can adapt the plugin (e.g. add live-preview or leaf-jump later) without editing core code.
27. As a power user, I want to **override any kind glyph** in config, so that I can match my own icon preferences.
28. As a config maintainer, I want the plugin **lazy-loaded on the `;` key**, so that it adds nothing to startup time.
29. As a config maintainer, I want the tree logic kept **pure and free of window calls**, so that the code stays simple to reason about and change.

## Implementation Decisions

- **Distribution:** a local Lua module under `lua/symboltree/`, surfaced to
  lazy.nvim through a thin one-file spec (`lua/plugins/symboltree.lua`) that
  lazy-loads on the `;` keymap. Not a `dir=`'d fake plugin.

- **Module split (four small files):**
  - `init.lua` — public API `setup(opts)` and `toggle()`, plus the config
    table (keymap→action map, glyph overrides, border, width/height clamps,
    window position). This is the extensibility surface.
  - `lsp.lua` — issues `textDocument/documentSymbol`, and **normalizes** both
    response shapes into one internal node type.
  - `tree.lua` — **pure** tree logic: flatten expanded nodes into renderable
    rows, hold fold state, and compute expand / collapse / parent-hop /
    expand-all / collapse-all transitions. Contains **no Neovim window calls**.
  - `ui.lua` — the float: create/size/position the window & scratch buffer,
    render rows, apply highlights, and wire keymaps to actions.

- **Internal node shape (normalization target):**
  `{ name, kind, range, selection_range, children }`. `DocumentSymbol[]` maps
  directly (recursing `children`); `SymbolInformation[]` maps to nodes with
  empty `children`, using `location.range` for both `range` and
  `selection_range`. One renderer consumes both.

- **Data flow:** the request fires on `toggle()` open; the float is built and
  shown in the **async response callback**. No caching — always live.

- **Multiple clients:** request from every attached client that supports
  `documentSymbol`; merge their top-level results into one root list.

- **Interaction model:** the **fold model** — the visible tree is a flat list
  of rows derived from the node tree + fold state. `j`/`k` move the cursor
  across all visible rows. `l` expands a branch (no-op on a leaf). `h`
  collapses an expanded branch; on an already-collapsed node or a leaf it moves
  the cursor to the parent row. `<CR>` reads the node under the cursor, closes
  the float, and jumps the origin window to `selection_range.start`. `zR`/`zM`
  expand-all / collapse-all and re-render.

- **Open state:** fully expanded; cursor set to the row whose node's `range`
  contains the origin cursor position (deepest enclosing match), falling back
  to row 1.

- **Toggle & restore:** `toggle()` opens+focuses if closed, closes if already
  open. On close-without-jump, the origin window and cursor are restored. The
  origin window/cursor are captured at open time.

- **Rendering:** each row is `<indent><chevron-or-space><glyph> <name>`, indent
  = 2 spaces per depth. Chevron shows only on branches (collapsed vs expanded
  glyphs). A built-in `SymbolKind → nerd-font glyph` table drives the icons,
  overridable via config.

- **Highlighting:** kind glyph + name are highlighted by highlight groups that
  **link to the colorscheme's existing groups** (e.g. Function→`Function`,
  Class→`Type`, Variable→`Identifier`), defined once at setup so they follow
  theme changes.

- **Window:** always a **floating** window with a **rounded border** and title
  ` Symbols `. Placement is driven by a **layout system** (`opts.window.layout`),
  one of five presets — `center` | `left` | `right` | `top` | `bottom` —
  **or** a function `function(ctx) -> { relative, row, col, width, height,
  anchor? }` (escape hatch). **Default is `right` with `height = "max"`.**
  Docked layouts (left/right/top/bottom) sit **flush against their edge** and
  are **centered on the free axis**; center sits in the middle.

- **Layout sizing:** each layout has its own `width`/`height` under
  `opts.window.layouts.<name>`. Every size value (and the `max_*` bounds) accepts
  one of four forms: **integer** (absolute cells), **float in (0,1)** (fraction
  of the editor dimension), **`"max"`** (fill the axis, editor minus border and
  command-line chrome), or **`"fit"`** (hug content, clamped by
  `min_width`/`max_width`/`min_height`/`max_height`). `"fit"` dimensions re-fit
  as you fold; `"max"`/fixed/fraction dimensions hold their shape. `center`
  defaults both axes to `"fit"` (its previous content-hug behavior); docked
  layouts default the docked panel to a fixed size with the cross-axis
  `"max"`imized. Border is drawn outside the sizing box, so resolved geometry is
  inset one cell from each editor edge and can never clip or overlap the command
  line. Runtime layout switching is out of scope (config-time only).

- **Empty/error handling:** if no client supports the method or the merged
  result is empty, `vim.notify` a short message and do **not** open a float.

## Testing Decisions

**Out of scope.** This is a personal Neovim configuration with no test runner
and no existing specs; standing up plenary/busted for a single local plugin is
not warranted here. Testing is instead served structurally: `tree.lua` is kept
**pure and free of Neovim window calls** (node tree + fold state in →
renderable rows and fold transitions out), and `lsp.lua`'s normalization is a
pure function over LSP response tables. That purity keeps both trivially
testable *should* a test runner ever be introduced, and easy to verify by hand
in the meantime. Verification for this feature is manual: exercise `;`, the
`h`/`j`/`k`/`l` navigation, `<CR>` jump, `zR`/`zM`, close/restore, and the
flat-vs-nested and empty/no-client cases in real buffers.

## Out of Scope

- **Live preview** — moving the origin buffer's cursor as you `j`/`k` through
  the tree. The action layer is designed to accommodate it later; not built in v1.
- **Leaf-`l` jump** — `l` on a leaf is a deliberate no-op in v1 (rebindable
  later via the action map).
- **Indent guide characters** (`│  `) — v1 uses plain spaces; a guide toggle is
  a later addition.
- **Symbol filtering / search / fuzzy narrowing** inside the float.
- **Caching or incremental updates** — every open is a fresh request.
- **Workspace symbols** (`workspace/symbol`) — this is document-scoped only.
- **A test runner / CI** — see Testing Decisions.
- **Non-LSP sources** (Treesitter fallback) — LSP only in v1.

## Further Notes

- `;` is free: the previous binding was `dropbar_api.pick`, and `dropbar.lua`
  is `enabled = false`.
- No `mini.icons`; symbol-kind glyphs ship as a built-in table (the standard
  approach, as dropbar/lspsaga do). `nvim-web-devicons` is present but provides
  file-type, not symbol-kind, icons.
- The user runs a nerd font, so glyphs render.
- "Keep the flexibility" is a cross-cutting requirement, realized by the
  keymap→action config table and the position preset-or-function.
