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
| 8 | Live filter | Permanent top-line search bar; `f` (or `@`) opens an editable prompt that narrows the outline live to matches + ancestors. Query mixes a name substring (smartcase) and an `@kind` token **in any order** (`proc @function` == `@function proc`); the `@` token is a prefix over the provider's kind names (SymbolKind for symbols, `file`/`dir` for files), ANDed with the name. The bar's leading search icon lights up (grey → highlighted) as the edit-mode signal. Any leave key (`<CR>`/`<Esc>`/`<C-c>`) hands the **real cursor** to the narrowed tree (`j/k/l/h` browse, `<CR>` jumps); `F` clears the filter; non-destructive to folds |
| 9 | Pinned symbols | `p` toggles a pin on the row; pinned symbols carry a right-aligned number badge, are numbered by document order, force-shown under collapsed parents, and jumped to with `1`–`9`. Pins persist **on disk** (single JSON), keyed by name+kind+ancestor-path, pruned when they no longer match. Shell owns the store/window/keys; the provider supplies `pin_key`/`pin_match` |

> Decision 9 deliberately reopens two earlier ones: **7b** (content is otherwise
> no-disk state — pins are the one exception, a tiny JSON store) and it was
> considered against **4** (a first sketch used a second sticky footer float; it
> was dropped in favor of in-place badges to keep the singleton-float model and
> the plugin's "keep everything simple" ethos).

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
        close = { "q", ";" },
      },
      layouts = { right = { width = 30 } }, -- per-provider geometry override
      content = {                          -- coarse per-layout toggles read by the render fn
        right  = { show_lnum = false },
        center = { show_lnum = true },
      },
      search = {                           -- live filter (permanent top-line bar)
        enabled = true,
        key = "f",                         -- opens the editable prompt
        clear_key = "F",                   -- clears an applied filter (back to full tree)
        hint = "f to filter",              -- idle hint (grey), after the icon
        prompt = "> ",                     -- leading icon: grey idle, highlighted while typing
        editing_hint = "name @kind",       -- grey example shown while typing an empty query
        placeholder = "(no matches)",
        keys = {                           -- prompt (insert-mode) keys
          leave = { "<CR>", "<Esc>", "<C-c>" }, -- all hand off to normal-mode browsing (none jump)
        },
        hl = { prompt = "Comment", hint = "Comment", editing = "Special", match = "Search", context = "Comment", selection = "Visual" },
      },
      pins = {                             -- pinned symbols (on-disk, name+kind+path keyed)
        enabled = true,
        key = "p",                         -- toggle a pin on the current row
        jump_keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }, -- jump to pin N
        hl = "Number",                     -- right-aligned badge highlight
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
- `make_matcher(query)` → `fn(node) -> false | { span }` — the live-filter predicate. The shell force-shows matched nodes + ancestors; `span` is an optional 0-based name-highlight range (nil for a match with nothing to underline). Provider-owned because only it knows what a `SymbolKind` is named.
- `pin_key(node)` → `string` and `pin_match(roots, key)` → `node | nil` — the pin identity pair (mirrors `make_matcher`). Provider-owned because only it knows what makes a symbol stably identifiable; the shell owns the store, badges, keys, and numbering.
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
- **Follow mode (symbols only, `providers.symbols.follow`):** when `enabled`, a
  `CursorMoved` autocmd on the float previews the hovered node in the origin
  window — paints `node.range` whole-line with `follow.hl` (a `driftwood_follow`
  namespace on the *origin* buffer) and moves the origin cursor to
  `selection_range.start`, `zz`-recentered when `follow.recenter`. Both the scroll
  and cursor set run inside `nvim_win_call` (no `WinLeave`, so no self-close;
  focus stays in the float). Browsing is non-destructive: `winsaveview()` is
  snapshotted on open and `winrestview`d on any cancel (close key or click-away);
  only `jump` (`<CR>`) commits and skips the restore. Node-cached on
  `state.follow_node` so redundant fires are no-ops. Disabled → no snapshot, no
  cursor move, no paint (zero behavior change).
- **Live filter (`providers.symbols.search`):** the float reserves **buffer line
  0** as a permanent search bar (tree shifts to lines 1..N; all row↔line math is
  offset by one). It has three states, keyed off `state.filter = { query, sel,
  typing }`:
  1. **Unfiltered** (`query == ""`, not typing): the full fold-honoring tree; the
     bar shows the `hint` as inline virtual text.
  2. **Typing** (`typing == true`): the `key` (`f`) opens the prompt (the provider's
     kind sigil `@` opens the same prompt pre-seeded with `@`, so kind mode is one
     keystroke away) — line 0
     becomes editable (`modifiable` on, `startinsert`), the leading `prompt` icon
     (`> `) switches to its highlighted `hl.editing` colour to signal the edit mode,
     and an `editing_hint` example (`name @kind`) trails it until the user starts
     typing, then drops. A
     `TextChangedI` autocmd re-filters on each edit via `tree.flatten_filtered`,
     driven by the provider's `make_matcher(query)`. The query mixes, **in any
     order**, a **name substring** (smartcase) and an `@kind` token: the text after
     `@` is a case-insensitive **prefix** over the provider's kind names (SymbolKind
     for symbols — `@c` → Class/Constructor/Constant; `file`/`dir` for files),
     unioned across every kind it prefixes, ANDed with the name (`proc @function` ==
     `@function proc`). A match keeps the node plus its **ancestor path** (force-shown;
     ancestor-only rows flagged `is_context`, rendered dimmed; matched substring in
     `hl.match`). The **first match** is highlighted (a `line_hl` extmark, the caret
     parks on the prompt) and follow-previewed. Any **leave key** (`<CR>`/`<Esc>`/`<C-c>`,
     config `search.keys.leave`) hands off to state 3 — none jump or close.
  3. **Filtered-normal** (`query ~= ""`, not typing): the narrowed tree is browsed
     with the **real cursor** — `j/k/l/h` and `<CR>` (jump) behave exactly as in the
     unfiltered tree, `CursorMoved` drives follow-mode. The bar shows the applied
     query as static line-0 text behind the `prompt` glyph. Fold ops (`l/h/zR/zM`)
     stand down here so they can't mutate `node.expanded` (`h` still hops to parent
     as navigation). `f` re-opens the prompt **pre-filled** to refine.

  Filtering **never mutates `node.expanded`**, so clearing restores the exact prior
  folds for free. The normal-mode `F` (`search.clear_key`) clears an applied filter
  (state 3 → full tree, landing on the browsed symbol); with no filter it's a no-op —
  it does **not** close the float. Only `q`/`;` close. No matches → a
  dimmed `placeholder` line, nothing to jump to. Disabled → no bar, no key, no
  `<Esc>` override, zero change.

- **Pinned symbols (`providers.symbols.pins`):** `p` (config `pins.key`) toggles a
  pin on the row under the cursor. Pins are a stable-identity, on-disk concept, so
  they survive close/reopen **and** nvim restart — the one exception to the
  otherwise no-disk snapshot model (decision 7b).

  *Identity + store (shell-owned, generic).* A pin is a **string key**, not a node
  reference (nodes are freshly fetched every open). The key is provider-built —
  for `symbols`, `pin_key(node)` = the `kind:name` path from the root down to the
  node (`5:MyClass/6:handle`), stable across the symbol moving lines and
  disambiguating same-named symbols by their container path. The store is a single
  JSON file at `stdpath("data")/driftwood/pins.json`: `{ [abs_path] = { key, … } }`,
  loaded once into a module table and **written through on every toggle** (tiny
  file; durable against a crash, no save-on-exit). The file key is the origin
  buffer's absolute path; an unnamed/scratch buffer has no path, so pins no-op.

  *Prune on open.* Symbols are re-fetched each open, so on open the shell runs
  `provider.pin_match(roots, key)` for every stored key of that file and **drops
  any key that no longer matches** (renamed/deleted symbol), rewriting the store if
  it changed. There is no persistent "stale pin" state — a pin either resolves to a
  live node or is pruned.

  *Numbering + badge.* The matched pinned nodes are numbered **1..N by document
  order** (a pre-order walk of `roots` = top-to-bottom display order), so a pin's
  number is stable and independent of folds or the active filter. Each pinned
  node's row draws its number as a **right-aligned virtual-text extmark**
  (`virt_text_pos = "right_align"`, its own `ns_pin` namespace, `pins.hl`), so the
  badge sits at the window's right edge in every layout without padding the buffer
  text or perturbing `"fit"` sizing — the one adjustment is that `refit` reserves
  the badge's width so a `"fit"`-width window can't clip it. It coexists with the
  `center` layout's `show_lnum` (that's mid-row text; the badge floats at the edge).

  *Force-show under folds.* Pinned nodes must be visible even inside a collapsed
  ancestor. `tree.flatten(roots, pinned)` takes the pinned set and, when it
  descends into a collapsed branch, emits **only** pinned descendants plus the
  ancestor chain down to them (ancestors flagged `is_context`, rendered dimmed like
  the filter's context rows). The collapsing parent keeps its collapsed chevron yet
  still shows the pinned child beneath it — the accepted oddity that makes "always
  visible" hold. With no pins the walk is byte-for-byte the old fold-honoring
  flatten. Force-show applies **only to the unfiltered view**: under an active
  filter the matcher alone decides rows (pinned non-matches are *not* forced in),
  though a pinned row that *does* match still shows its badge.

  *Jump.* `1`–`9` (config `pins.jump_keys`), bound in the float, jump to that pin
  number via the provider's `jump` action (commits + closes, exactly like `<CR>`).
  It resolves through the pin set, so it works even when the filter currently hides
  that pin. Cost: digits shadow vim count-prefixes inside the float (rebindable to a
  leader). In the typing state the caret is on the prompt (insert mode), so digits
  type into the query instead. Disabled (or scratch buffer) → no badges, no `p`, no
  digit keys, zero change.

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
