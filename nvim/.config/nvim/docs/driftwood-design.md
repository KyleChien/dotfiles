# driftwood — design

`driftwood` is a generic **flexible floating-window shell** that wraps a
*provider* (content source) and lets you move the window between five layouts at
runtime. It is the refactor of `symboltree`, which becomes driftwood's first
provider: `symbols` (the LSP document-symbol outline).

## Guiding decision: refactor-in-place, extract-later (approach A)

There is exactly **one** real provider today. We do **not** freeze a public
`Provider` interface, genericize the node model, or build a plugin framework
around a hypothetical file explorer. We separate the symbol-specific code from a
generic shell along clean module boundaries, add runtime layout switching, and
let the true provider contract reveal itself when a *second* concrete provider
actually exists. Everything below is scoped by that discipline.

## Decisions locked

| # | Decision | Choice |
|---|----------|--------|
| 1 | Abstraction level | Refactor-in-place; no frozen provider interface yet |
| 2 | Layout-switch keys | Direct: `H`=left `J`=bottom `K`=top `L`=right `M`=center, on by default, rebindable |
| 3 | Per-layout content | Layout-aware render function per provider (not a declarative field engine) |
| 4 | Concurrency | Singleton — one float at a time; `WinLeave`-autoclose stays |
| 5 | Config hierarchy | Global window config + per-provider override, `deep_extend("force", …)` |
| 6 | Public API | Nested `providers = { symbols = {…} }`; each provider owns its toggle `key` |
| 7a | Layout persistence | Sticky **in-session** (module-level `last_layout[provider]`); resets on nvim restart |
| 7b | Content freshness | Snapshot on open; no auto-refresh (reopen to refresh) |

## Config boundary — window vs content

The split is "is this about the **window** or the **content**?"

**Global (every provider shares):**
- `layouts` — the five geometry specs (`width`/`height`/`min_*`/`max_*`, position semantics). Default window shapes.
- `layout_keys` — `H/J/K/L/M`. Universal muscle memory; **global-only**, not per-provider.
- `border` and generic chrome.

**Per-provider (`symbols` owns):**
- `key` — this provider's toggle key.
- `icons`, `kind_hl`, `title`, `initial_depth`.
- `keys` — nav/action bindings (`j/k/h/l/<CR>/q`); provider-specific because actions differ (jump-to-symbol ≠ open-file).
- per-layout content toggles (e.g. `show_lnum`).
- optional `layouts` override — deep-merged over global geometry.

Resolved geometry for the active provider =
`deep_extend("force", global.layouts, provider.layouts)`.

## Config schema

```lua
require("driftwood").setup({
  -- ── global (window) ──────────────────────────────────────────────
  layouts = {
    center = { width = "fit", height = "fit", min_width = 30, max_width = 60, max_height = 0.6 },
    left   = { width = 30, height = "max" },
    right  = { width = 30, height = "max" },
    top    = { height = 15, width = "max" },
    bottom = { height = 15, width = "max" },
  },
  layout_keys = { left = "H", bottom = "J", top = "K", right = "L", center = "M" },
  border = "rounded",

  -- ── providers (content) ──────────────────────────────────────────
  providers = {
    symbols = {
      key = ";",                       -- toggle key for this provider
      title = " Symbols ",
      initial_depth = 1,
      keys = {
        down = "j", up = "k", expand = "l", collapse = "h",
        jump = "<CR>", expand_all = "zR", collapse_all = "zM",
        close = { "q", "<Esc>", ";" },
      },
      layouts = { right = { width = 30 } }, -- per-provider geometry override
      content = {                          -- coarse per-layout toggles read by the render fn
        right  = { show_lnum = false },
        center = { show_lnum = true },
      },
      icons = { --[[ SymbolKind → glyph ]] },
      kind_hl = { --[[ SymbolKind → hl group ]] },
    },
  },
})
```

## Module structure

```
lua/driftwood/
  init.lua        -- setup, config merge, registry, toggle(name)/open(name)/close()
  window.lua      -- geometry resolution + layout switching (from ui.lua's geometry half)
  render.lua      -- generic flatten → buffer → highlight loop, calls provider render(row, layout)
  tree.lua        -- pure fold/flatten/find_enclosing  (moved unchanged — already generic)
  providers/
    symbols.lua   -- lsp fetch+normalize + build_line(row, layout, cfg) + jump action + icons/kind_hl
```

**Where today's files go:**
- `tree.lua` → `driftwood/tree.lua` — untouched; it already operates on opaque nodes.
- `lsp.lua` → folded into `providers/symbols.lua` (fetch + normalize).
- `ui.lua` splits:
  - geometry (`usable_area`, `resolve_extent`, `resolve_dim`, `compute_geometry`, `win_config`) → `window.lua`
  - the generic render loop (`render`, `add_hl`, cursor movement, keymap wiring, open/close, `WinLeave`) → `render.lua`
  - the symbol-specific `build_line` and the `jump` action → `providers/symbols.lua`
- `init.lua` → `driftwood/init.lua`: merges global + provider config, registers each provider's toggle key.

## The seam

`state` stays a single record but no longer hard-codes "symbols." It holds a
reference to the **active provider**:

```lua
state = {
  win, buf,
  provider,        -- the resolved symbols provider table
  cfg,             -- resolved config (global ⊕ provider)
  roots, rows,     -- the cached tree + current visible rows
  layout,          -- active layout name (mutated by H/J/K/L/M)
  origin_win,
}
```

A provider supplies, informally (no enforced interface yet):
- `fetch(bufnr, cb)` → calls back with a node tree (or nil).
- `render(row, layout, cfg)` → `text, segments` — the layout-aware line builder.
- `actions` — its action table (`jump` etc.); the generic `down/up/expand/collapse/close` live in the shell.
- static tables: `icons`, `kind_hl`, defaults.

The shell (`window` + `render` + `tree`) never mentions symbols, LSP, or ranges.

## Runtime behaviors

- **Layout switch:** pressing a `layout_keys` key sets `state.layout`, records it
  in the in-session `last_layout[provider_name]`, and re-runs `render()` against
  the **cached** tree (no re-fetch). `render()` already recomputes `content_dims`
  and re-fits `"fit"` dimensions, so `right → center` re-expands the window and
  the provider's `render` emits the richer per-layout content for free.
- **Sticky-in-session:** on open, `state.layout = last_layout[name] or provider.default_layout`.
  A module-level table; nvim restart clears it. No disk state.
- **WinLeave-autoclose:** unchanged. Layout switching keeps focus in the float,
  so it never trips the autoclose.
- **Snapshot content:** tree fetched once on open; edits go stale until reopen.

## Implementation sequence (safe, incremental)

1. **Rename shell, no behavior change.** Copy `lua/symboltree/` → `lua/driftwood/`,
   rename module strings, add a `driftwood` lazy spec, confirm `;` still toggles
   the outline identically. (Keep `symboltree` until parity is proven, then delete.)
2. **Carve `window.lua` out of `ui.lua`.** Move geometry helpers; `ui`/`render`
   calls into it. No behavior change.
3. **Introduce the provider seam.** Move `build_line` + `jump` + lsp fetch into
   `providers/symbols.lua`; have the render loop call `provider.render`. Still one
   provider, identical output.
4. **Config hierarchy.** Restructure config into global + `providers.symbols`;
   implement the `deep_extend` geometry merge and per-provider key registration.
5. **Runtime layout switching.** Add `layout_keys`, the switch action, and
   `last_layout` sticky state.
6. **Per-layout content.** Make `symbols.render` branch on `layout` + read
   `content[layout].show_lnum`. Verify `right` (name only) vs `center` (+ lnum).

Each step is a self-contained commit that leaves the plugin working.

## Explicitly deferred (YAGNI)

- A frozen/public `Provider` interface — designed against the *second* real provider.
- Genericized node model — nodes stay LSP-shaped inside `symbols`; the shell treats them as opaque (`children`/`expanded`/`parent` only).
- Multi-instance / side-by-side panes — needs a collection state model + edge-collision; deferred with the singleton.
- Auto-refresh on buffer change — debounced autocmds + fold/cursor preservation; reopen-to-refresh for now.
- Declarative per-layout field engine — a mini-language for one provider; the render function covers it.
- Persistent (on-disk) layout memory — in-session only.
```
