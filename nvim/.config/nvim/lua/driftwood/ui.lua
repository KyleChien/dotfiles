-- driftwood.ui — the floating window: create/size/position, render rows with
-- highlights, and wire keymaps to actions. All Neovim-coupled code lives here.

local tree = require("driftwood.tree")
local window = require("driftwood.window")
local pins = require("driftwood.pins")

local M = {}
local ns = vim.api.nvim_create_namespace("driftwood")
-- The right-aligned pin-number badges. Its own namespace so it can be repainted
-- on each render without touching content highlights in `ns`.
local ns_pin = vim.api.nvim_create_namespace("driftwood_pin")
-- Separate namespace for the follow-mode highlight painted in the *origin*
-- buffer (the outline lives in `ns` on the float buffer).
local ns_follow = vim.api.nvim_create_namespace("driftwood_follow")
-- The search bar's inline virtual text (prompt glyph / idle hint) on line 0.
local ns_bar = vim.api.nvim_create_namespace("driftwood_bar")
-- The first-match highlight painted while typing a query. Its own namespace so it
-- can be repainted on each keystroke without touching the content highlights in `ns`.
local ns_sel = vim.api.nvim_create_namespace("driftwood_sel")
-- Edit mode (oil-style): one extmark per editable line, tagging it with its source
-- node so the commit diff can tell rename/move (mark survived) from create (no mark).
local ns_edit = vim.api.nvim_create_namespace("driftwood_edit")

-- The float reserves buffer line 0 for the search bar; the tree occupies lines
-- 1..N. So tree row i (1-based, into state.rows) lives on 0-based buffer line i,
-- i.e. cursor line i + 1. All the row<->line math below honors that offset.
--
-- state = { win, buf, cfg, provider, roots, rows, origin, origin_win, origin_buf,
--           origin_view, follow_node,
--           filter = { query, sel, typing }, search_aucmds, search_maps, rendering,
--           loading, token, spin_frame, spin_timer }
-- While `loading` (fetch in flight) roots/rows are empty and only the spinner +
-- close keys are live; M.populate flips it off and wires the rest. `token` (a
-- monotonic id from open_seq) guards the async fetch callback.
--
-- The live filter has three states, keyed off `filter`:
--   1. unfiltered      — query == "", not typing: the full fold-honoring tree.
--   2. typing (insert) — typing == true: line 0 is an editable prompt, the tree
--      narrows live on each keystroke, the first match is highlighted+previewed.
--   3. filtered (normal) — query ~= "", not typing: the narrowed tree is browsed
--      with the *real* cursor (j/k), exactly like the unfiltered tree.
-- `/` moves 1→2 (and 3→2 to refine); <CR> in 2 jumps to the first match; <Esc>
-- in 2 hands the cursor to the tree (2→3); <Esc> in 3 clears the filter (3→1).
local state = nil

-- Sticky-in-session layout: provider name -> last layout the user switched to.
-- Cleared on nvim restart; never written to disk.
local last_layout = {}

-- Sticky-in-session fold level, keyed by the provider's fold scope:
-- "provider\0scope" -> last level the user set (via </>, zM/zR). The scope is the
-- provider's fold_scope (files: the tree root, so a project's depth is shared) or
-- the origin file (symbols: per-file). Restored on the next open with the same
-- scope in place of the configured initial_depth. Session-only, never persisted.
local last_fold_level = {}
local function fold_key()
  return state.provider.name .. "\0" .. (state.fold_scope or "")
end

-- ── rendering ──────────────────────────────────────────────────────────────
-- Row content is provider-owned: state.provider.render(row, cfg) returns the
-- line text plus a list of { start_col, end_col, hl_group } byte spans. The loop
-- below is otherwise provider-agnostic.

local function add_hl(line, start_col, end_col, group)
  vim.api.nvim_buf_set_extmark(state.buf, ns, line, start_col, {
    end_row = line,
    end_col = end_col,
    hl_group = group,
  })
end

-- ── content measurement ─────────────────────────────────────────────────────

-- Longest visible row (display cells) and row count. +2 pads the width so text
-- doesn't touch the border when a dimension is "fit". Fed to driftwood.window
-- so "fit" dimensions can hug the rendered content.
local function content_dims(lines)
  local w = 1
  for _, l in ipairs(lines) do
    w = math.max(w, vim.fn.strdisplaywidth(l))
  end
  return w + 2, #lines
end

-- Is a filter query in effect (states 2 & 3)? Drives filtered flatten, the bar
-- prompt, and whether fold ops must stand down to keep folds intact.
local function filtering()
  return state and state.filter and state.filter.query ~= ""
end

-- Is the editable prompt currently open (state 2)? Only then is line 0 editable,
-- the caret pinned to the bar, and the first-match highlight painted.
local function typing()
  return state and state.filter and state.filter.typing
end

-- Is oil-style edit mode active? The whole tree buffer is editable text; browse
-- actions (fold, filter, pins, layout) stand down until commit/abort.
local function editing()
  return state and state.edit and state.edit.active
end

-- The rows to display: filtered when a non-empty query is in effect, else the
-- full fold-honoring tree. Filtering never mutates node.expanded, so clearing the
-- query restores the exact prior folds. Matching is provider-owned: the provider
-- turns the query into a per-node predicate (name substring, @kind filter, …); a
-- provider without make_matcher simply can't filter.
local function compute_rows()
  if filtering() and state.provider.make_matcher then
    return tree.flatten_filtered(state.roots, state.provider.make_matcher(state.filter.query))
  end
  -- Unfiltered: force-show pinned nodes (state.pinned may be nil → plain flatten).
  return tree.flatten(state.roots, state.pinned)
end

-- Paint the bar's inline virtual text on line 0: the prompt glyph while filtering,
-- otherwise the idle hint that advertises the trigger key. Lives in its own
-- namespace so tree-only redraws (on each keystroke) leave it untouched.
local function paint_bar()
  vim.api.nvim_buf_clear_namespace(state.buf, ns_bar, 0, -1)
  local search = state.cfg.search
  if not (search and search.enabled) then
    return
  end
  local shl = search.hl or {}
  local text, group
  -- Prompt glyph whenever a query is being typed (2) or is applied (3); the idle
  -- hint only in the unfiltered state (1).
  if typing() or filtering() then
    text, group = search.prompt or "", shl.prompt or "Comment"
  else
    text, group = search.hint or "", shl.hint or "Comment"
  end
  if text ~= "" then
    vim.api.nvim_buf_set_extmark(state.buf, ns_bar, 0, 0, {
      virt_text = { { text, group } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end
end

-- Paint the first-match highlight (whole line) while typing (state 2): the caret
-- sits on the bar, so this marks the row <CR> will jump to and follow previews.
-- In the filtered-normal state (3) the real cursor + cursorline shows position,
-- so this stands down.
local function paint_selection()
  vim.api.nvim_buf_clear_namespace(state.buf, ns_sel, 0, -1)
  if not typing() then
    return
  end
  local sel = state.filter.sel
  if not sel or not state.rows[sel] then
    return
  end
  local hl = (state.cfg.search.hl or {}).selection or "Visual"
  -- tree row `sel` (1-based) is on 0-based buffer line `sel`.
  vim.api.nvim_buf_set_extmark(state.buf, ns_sel, sel, 0, { line_hl_group = hl })
end

-- Measured display width of the bar (virtual prompt/hint isn't in the line text,
-- so add it explicitly) — lets "fit" layouts hug the wider of bar vs. tree.
local function bar_width()
  local search = state.cfg.search
  if not (search and search.enabled) then
    return 0
  end
  if typing() or filtering() then
    return vim.fn.strdisplaywidth((search.prompt or "") .. state.filter.query)
  end
  return vim.fn.strdisplaywidth(search.hint or "")
end

-- ── fold-level indicator (dot meter in the border title) ────────────────────
-- The dynamic fold level (state.fold_level, 0..state.max_level) is visualized as a
-- dot meter appended to the window title: one dot per foldable level, filled up to
-- the current level (e.g. "●●○○" = level 2 of 4). Recomputed on every geometry
-- apply so it tracks `<`/`>`, zM/zR live. Past `max_dots` levels it degrades to
-- "L/max" text so the title can't run away on absurdly deep trees.
local FOLD_MAX_DOTS = 8

local function fold_meter()
  local f = state and state.cfg.fold
  if not (f and state.max_level and state.max_level > 0) then
    return ""
  end
  local lvl = math.max(0, math.min(state.fold_level or 0, state.max_level))
  if state.max_level > FOLD_MAX_DOTS then
    return lvl .. "/" .. state.max_level
  end
  return string.rep(f.filled, lvl) .. string.rep(f.empty, state.max_level - lvl)
end

-- The border title for the current geometry apply: the base title, plus the fold
-- meter (as a separately-highlighted chunk) when the tree can fold. Returns a plain
-- string when there's no meter so the common case stays a bare title.
local function win_title()
  local base = (state and state.cfg.window.title) or ""
  local meter = fold_meter()
  if meter == "" then
    return base
  end
  local hl = (state.cfg.fold and state.cfg.fold.hl) or "Number"
  return { { base, "FloatTitle" }, { meter .. " ", hl } }
end

-- Re-fit the window to the given lines (plus the bar's virtual width, plus the
-- pin badges' reserved width so a "fit"-width window can't clip the right-aligned
-- badge — the badge isn't in the line text, so content_dims can't see it).
local function refit(lines)
  local cw, ch = content_dims(lines)
  cw = math.max(cw, bar_width() + 2)
  if state.badge_w and state.badge_w > 0 then
    cw = cw + state.badge_w + 1
  end
  local geo = window.compute_geometry(state.cfg, cw, ch)
  geo.title = win_title() -- append the live fold meter to the border title
  vim.api.nvim_win_set_config(state.win, window.win_config(geo, state.cfg))
end

-- Render the tree portion (buffer lines 1..N) from state.rows: line text +
-- content highlights + selection, then re-fit. `bar_text` is what should sit on
-- line 0. When `keep_bar_line` is true the caller has already put the query on
-- line 0 (the user is typing it) and we must not overwrite it; otherwise we
-- rewrite line 0 too. Content highlights live in `ns`; the bar's virtual text is
-- painted separately by paint_bar (callers that change bar mode call it).
local function render_rows(bar_text, keep_bar_line)
  state.rows = compute_rows()
  local cfg = state.cfg
  local shl = (cfg.search and cfg.search.hl) or {}

  local tree_lines, spans = {}, {}
  local no_match = filtering() and #state.rows == 0
  if no_match then
    local ph = "  " .. ((cfg.search and cfg.search.placeholder) or "(no matches)")
    tree_lines[1] = ph
    spans[1] = { { 0, #ph, shl.placeholder or "Comment" } }
  else
    for i, row in ipairs(state.rows) do
      tree_lines[i], spans[i] = state.provider.render(row, cfg, cfg.window.layout)
    end
  end

  state.rendering = true
  vim.bo[state.buf].modifiable = true
  if keep_bar_line then
    vim.api.nvim_buf_set_lines(state.buf, 1, -1, false, tree_lines)
  else
    local all = { bar_text }
    vim.list_extend(all, tree_lines)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, all)
  end
  vim.bo[state.buf].modifiable = typing() and true or false
  state.rendering = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, row_spans in ipairs(spans) do
    for _, s in ipairs(row_spans) do
      add_hl(i, s[1], s[2], s[3]) -- tree row i (1-based) -> 0-based buffer line i
    end
  end
  paint_selection()

  -- Pin badges: a right-aligned virtual-text number on each visible pinned row.
  -- Pinned even when a filter hides its force-show — a matching pinned row still
  -- shows its (document-order) number. Reserve the widest badge for "fit" sizing.
  vim.api.nvim_buf_clear_namespace(state.buf, ns_pin, 0, -1)
  state.badge_w = 0
  if state.pin_num and next(state.pin_num) and not no_match then
    local phl = (cfg.pins and cfg.pins.hl) or "Number"
    for i, row in ipairs(state.rows) do
      local n = state.pin_num[row.node]
      if n then
        local label = " " .. n .. " "
        vim.api.nvim_buf_set_extmark(state.buf, ns_pin, i, 0, {
          virt_text = { { label, phl } },
          virt_text_pos = "right_align",
        })
        state.badge_w = math.max(state.badge_w, vim.fn.strdisplaywidth(label))
      end
    end
  end

  local measured = { bar_text }
  vim.list_extend(measured, tree_lines)
  refit(measured)
end

-- Full render: rewrite line 0 (bar) and the tree, and repaint the bar's virtual
-- text. Used on open, layout switch, and entering/leaving the filter. Line 0 is
-- the current query (empty in the unfiltered state, so the bar reads blank and
-- the hint is drawn as virtual text over it).
local function render()
  render_rows(state.filter.query, false)
  paint_bar()
end

-- Force-open every ancestor of `node` so the node itself becomes visible, no matter
-- the current fold level. A targeted reveal (used to surface the focused file on
-- open) — like pins' force-show, it doesn't touch the fold meter / level.
local function reveal_ancestors(node)
  local n = node.parent
  while n do
    if n.children and #n.children > 0 then
      n.expanded = true
    end
    n = n.parent
  end
end

-- Move the cursor to `node`'s row; if it's not visible, climb to the nearest
-- visible ancestor. Falls back to the first tree row (buffer line 1 is the bar).
local function move_cursor_to_node(node)
  while node do
    for i, row in ipairs(state.rows) do
      if row.node == node then
        vim.api.nvim_win_set_cursor(state.win, { i + 1, 0 })
        return
      end
    end
    node = node.parent
  end
  local last = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_win_set_cursor(state.win, { math.min(2, last), 0 })
end

-- The tree row under the cursor and its 1-based index into state.rows (nil on the
-- bar line). Cursor line c corresponds to tree row c - 1.
local function current_row()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local idx = line - 1
  return state.rows[idx], idx
end

-- ── follow mode (live preview into the origin window) ────────────────────────
-- When cfg.follow.enabled, hovering a node paints its range in the origin buffer
-- and moves the origin cursor there. Browsing is non-destructive: origin_view is
-- snapshotted on open and restored on any close except a committing `jump`.

local function follow_on()
  return state and state.cfg.follow and state.cfg.follow.enabled
end

-- Wipe the follow highlight from the origin buffer.
local function clear_follow()
  local buf = state and state.origin_buf
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns_follow, 0, -1)
  end
end

-- Restore the origin window's cursor+view to the snapshot taken on open.
local function restore_origin_view()
  if not (state and state.origin_view) then
    return
  end
  local win = state.origin_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview(state.origin_view)
    end)
  end
end

-- Preview `node` in the origin window: paint its full range whole-line, then
-- place (and optionally recenter) the origin cursor on the symbol's name. Cached
-- on state.follow_node so redundant CursorMoved fires are cheap no-ops.
local function follow_preview(node)
  if not follow_on() or not node or node == state.follow_node then
    return
  end
  state.follow_node = node
  local win, buf = state.origin_win, state.origin_buf
  if not (win and vim.api.nvim_win_is_valid(win) and buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  clear_follow()
  local hl = state.cfg.follow.hl or "Visual"
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local r = node.range
  local s_line = math.max(0, math.min(r.start.line, last))
  local e_line = math.max(s_line, math.min(r["end"].line, last))
  for line = s_line, e_line do
    vim.api.nvim_buf_set_extmark(buf, ns_follow, line, 0, { line_hl_group = hl })
  end

  local target = node.selection_range.start
  local cur_line = math.max(0, math.min(target.line, last))
  local line_text = vim.api.nvim_buf_get_lines(buf, cur_line, cur_line + 1, false)[1] or ""
  local col = math.max(0, math.min(target.character, #line_text))
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_win_set_cursor(win, { cur_line + 1, col })
    if state.cfg.follow.recenter then
      vim.cmd("normal! zz")
    end
  end)
end

-- ── pins (on-disk, force-shown, number-jumped) ───────────────────────────────
-- The store (driftwood.pins) is generic; identity is provider-owned via pin_key/
-- pin_match. state carries three derived tables: `pinned` (node-set, for force-show),
-- `pin_num` (node -> number) and `pin_bynum` (number -> node, for digit jumps).

-- The on-disk pin store key. Defaults to the origin file (symbols: pins are per
-- file); a provider may override via pin_scope (files: pins are per tree root, so
-- they're shared regardless of which buffer was focused on open).
local function pin_scope()
  return state and state.pin_scope or ""
end

local function pins_enabled()
  return state and state.cfg.pins and state.cfg.pins.enabled and pin_scope() ~= ""
    and state.provider.pin_key and state.provider.pin_match
end

-- Number the pinned nodes 1..N by document order (pre-order = display order), so a
-- pin's number is stable regardless of folds or the active filter.
local function number_pins(roots, pinned)
  local num, bynum, n = {}, {}, 0
  local function walk(nodes)
    for _, node in ipairs(nodes) do
      if pinned[node] then
        n = n + 1
        num[node] = n
        bynum[n] = node
      end
      if node.children then
        walk(node.children)
      end
    end
  end
  walk(roots)
  return num, bynum
end

-- Rebuild the derived pin tables from the on-disk store: re-match every stored key
-- against the freshly-fetched tree, prune keys that no longer resolve (rewriting
-- the store), then renumber. Cheap; run on open and after each toggle.
local function refresh_pins()
  state.pinned, state.pin_num, state.pin_bynum = {}, {}, {}
  if not pins_enabled() then
    return
  end
  local keys = pins.get(pin_scope())
  local kept, pinned = {}, {}
  for _, key in ipairs(keys) do
    local node = state.provider.pin_match(state.roots, key, state.cfg)
    if node then
      pinned[node] = true
      kept[#kept + 1] = key
    end
  end
  if #kept ~= #keys then -- something was pruned
    pins.set_keys(pin_scope(), kept)
  end
  state.pinned = pinned
  state.pin_num, state.pin_bynum = number_pins(state.roots, pinned)
end

-- Toggle the pin on the row under the cursor: flip it in the store, rebuild the
-- derived tables, re-render (force-show + badges shift), keep the cursor put.
local function pin_toggle()
  if not pins_enabled() or editing() then
    return
  end
  local row = current_row()
  if not row then
    return
  end
  -- A provider may forbid pinning some nodes (files: folders aren't pinnable).
  if state.provider.can_pin and not state.provider.can_pin(row.node) then
    return
  end
  pins.toggle(pin_scope(), state.provider.pin_key(row.node))
  refresh_pins()
  render()
  move_cursor_to_node(row.node)
end

-- Jump to the pinned symbol numbered `n` (digit keys), if any — commits + closes
-- via the provider's jump, exactly like <CR>. Resolves through the pin set, so it
-- works even when the active filter currently hides that pin.
local function pin_jump(n)
  local node = state.pin_bynum and state.pin_bynum[n]
  if not node then
    return
  end
  local jump = state.provider.actions and state.provider.actions.jump
  if jump then
    jump({ node = node, origin_win = state.origin_win, close = M.close })
  end
end

-- Re-fetch the whole tree from the provider and re-render (used after an edit-mode
-- commit mutates the filesystem). Resets folds/filter to a fresh open; pins are
-- re-matched against the new tree.
local function reload_tree()
  if not state then
    return
  end
  local cfg = state.cfg
  state.provider.fetch(state.origin_buf, function(roots)
    if not state then
      return
    end
    roots = roots or {}
    tree.prepare(roots, cfg.initial_depth)
    state.roots = roots
    state.max_level = tree.max_level(roots)
    state.filter = { query = "", sel = 1, typing = false }
    refresh_pins()
    render()
    local last = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { math.min(2, last), 0 })
  end, cfg)
end

-- Leave edit mode's editable state (drop the line-tracking extmarks, make the
-- buffer read-only again). Callers follow with render() or reload_tree().
local function exit_edit()
  if not state then
    return
  end
  state.edit = nil
  vim.api.nvim_buf_clear_namespace(state.buf, ns_edit, 0, -1)
  vim.bo[state.buf].modifiable = false
end

-- ── actions (the rebindable behavior surface) ────────────────────────────────

local actions = {}

function actions.down()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  -- In edit mode the buffer holds arbitrary edited lines (not state.rows), so bound
  -- the cursor by the real line count instead.
  local last = editing() and vim.api.nvim_buf_line_count(state.buf) - 1 or #state.rows
  if line - 1 < last then -- a next line exists
    vim.api.nvim_win_set_cursor(state.win, { line + 1, 0 })
  end
end

function actions.up()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  if line > 2 then -- stay below the bar (line 1)
    vim.api.nvim_win_set_cursor(state.win, { line - 1, 0 })
  end
end

function actions.expand()
  -- Under a filter, matches are force-shown regardless of fold state, so folding
  -- is inert; mutating node.expanded here would also corrupt the folds we promise
  -- to restore on clear. Stand down (the row is already as expanded as it gets).
  if filtering() or editing() then
    return
  end
  local row = current_row()
  if row and row.has_children and not row.node.expanded then
    row.node.expanded = true
    render()
    move_cursor_to_node(row.node)
  end
end

function actions.collapse()
  if editing() then
    return
  end
  local row = current_row()
  if not row then
    return
  end
  -- Under a filter, don't touch folds (see actions.expand); keep only the useful
  -- "hop to parent" navigation.
  if filtering() then
    if row.node.parent then
      move_cursor_to_node(row.node.parent)
    end
    return
  end
  if row.has_children and row.node.expanded then
    row.node.expanded = false
    render()
    move_cursor_to_node(row.node)
  elseif row.node.parent then
    move_cursor_to_node(row.node.parent)
  end
end

-- Set the fold level *and* remember it for this session, so the next open of this
-- same file restores it (see M.populate). Session-only, keyed per file.
local function remember_fold_level(level)
  state.fold_level = level
  last_fold_level[fold_key()] = level
end

function actions.expand_all()
  if filtering() or editing() then -- folds are inert under a filter; leave them intact
    return
  end
  local row = current_row()
  tree.set_expanded_all(state.roots, true)
  remember_fold_level(state.max_level) -- fully open: sync the meter to max
  render()
  if row then
    move_cursor_to_node(row.node)
  end
end

function actions.collapse_all()
  if filtering() or editing() then -- folds are inert under a filter; leave them intact
    return
  end
  local row = current_row()
  tree.set_expanded_all(state.roots, false)
  remember_fold_level(0) -- fully folded: sync the meter to 0
  render()
  if row then
    move_cursor_to_node(row.node)
  end
end

-- ── dynamic fold level ───────────────────────────────────────────────────────
-- Uniformly fold/unfold the whole tree by one level, like vim's zm/zr. Setting a
-- level overrides any manual l/h folds (it's a uniform depth), and the title meter
-- redraws to match. Clamped to [0, max_level]; a no-op at the ends and under a
-- filter (where folds are inert and must stay intact for the clear-to-restore).
local function set_fold_level(level)
  if editing() then
    return
  end
  level = math.max(0, math.min(level, state.max_level or 0))
  if level == state.fold_level then
    return
  end
  remember_fold_level(level)
  local row = current_row()
  tree.set_expanded_depth(state.roots, level)
  render()
  if row then
    move_cursor_to_node(row.node)
  end
end

function actions.fold_more() -- unfold one level (open deeper) — the `>` key
  if filtering() then
    return
  end
  set_fold_level((state.fold_level or 0) + 1)
end

function actions.fold_less() -- fold one level (close deeper) — the `<` key
  if filtering() then
    return
  end
  set_fold_level((state.fold_level or 0) - 1)
end

function actions.close()
  M.close(true)
end

-- ── activate / lazy dirs / hidden toggle ─────────────────────────────────────

-- Generic "open or toggle" for tree providers with expandable containers: on a
-- branch (directory) toggle its fold (loading children first); on a leaf (file)
-- run the provider's jump. Opt-in via cfg.keys.activate (files maps it to <CR>).
function actions.activate()
  if editing() then
    return
  end
  local row = current_row()
  if not row then
    return
  end
  if row.has_children then
    if row.node.expanded then
      actions.collapse()
    else
      actions.expand()
    end
  else
    local jump = state.provider.actions and state.provider.actions.jump
    if jump then
      jump({ node = row.node, origin_win = state.origin_win, close = M.close })
    end
  end
end

-- Flip a provider's hidden-file visibility (dotfiles/gitignore) and reload. No-op
-- for providers without the hook.
function actions.toggle_hidden()
  if editing() or not state.provider.toggle_hidden then
    return
  end
  state.provider.toggle_hidden()
  reload_tree()
end

-- ── oil-style edit mode ──────────────────────────────────────────────────────
-- `edit` flips the tree buffer into editable text (each row re-serialized to a
-- clean `indent + name` line, tagged with a line-tracking extmark). `commit`
-- diffs the edits into a file-op list, previews it, and applies on confirm;
-- `abort` discards. Gated on the provider declaring `editable` + the edit hooks.

function actions.edit()
  if not state or filtering() or editing() then
    return
  end
  if not (state.provider.editable and state.provider.edit_serialize) then
    return
  end
  local buf = state.buf
  -- Clean the float of browse decorations (content hl, pin badges, selection, bar).
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, ns_pin, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, ns_sel, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, ns_bar, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, ns_edit, 0, -1)

  local originals = {}
  local lines = {}
  for i, row in ipairs(state.rows) do
    lines[i] = state.provider.edit_serialize(row)
    originals[#originals + 1] = { path = row.node.path, is_dir = row.node.is_dir }
  end
  state.edit = { active = true, by_id = {}, originals = originals }

  local hint = (state.cfg.edit and state.cfg.edit.hint) or "-- EDIT — write:<C-s>  abort:<C-c> --"
  state.rendering = true
  vim.bo[buf].modifiable = true
  local all = { hint }
  vim.list_extend(all, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all)
  state.rendering = false
  add_hl(0, 0, #hint, (state.cfg.search and state.cfg.search.hl and state.cfg.search.hl.prompt) or "Comment")

  -- Tag each content line (tree row i → buffer line i) with its source path, so the
  -- commit diff can pair edited lines back to the nodes they came from.
  for i, row in ipairs(state.rows) do
    local id = vim.api.nvim_buf_set_extmark(buf, ns_edit, i, 0, { right_gravity = false })
    state.edit.by_id[id] = row.node.path
  end
  vim.wo[state.win].cursorline = true
end

function actions.abort()
  if not editing() then
    return
  end
  exit_edit()
  render()
  local last = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_win_set_cursor(state.win, { math.min(2, last), 0 })
end

function actions.commit()
  if not editing() then
    return
  end
  local buf = state.buf
  local raw = vim.api.nvim_buf_get_lines(buf, 1, -1, false) -- skip bar line 0

  -- Map each current buffer line (0-based) to the path it originally held, via the
  -- surviving extmarks. A line with no mark is a freshly typed one (→ create).
  local line_path = {}
  for _, mk in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns_edit, 0, -1, {})) do
    line_path[mk[2]] = state.edit.by_id[mk[1]]
  end
  local entries = {}
  for idx, text in ipairs(raw) do
    entries[#entries + 1] = { text = text, orig_id = line_path[idx] } -- raw[idx] is buffer line idx
  end

  local tree_root = pin_scope()
  if tree_root == "" then
    tree_root = state.origin_path
  end
  local ops = state.provider.parse_edit(entries, state.edit.originals, tree_root)
  if #ops == 0 then
    exit_edit()
    render()
    return
  end

  local preview = state.provider.preview_ops(ops)
  local choice =
    vim.fn.confirm("Apply file changes?\n\n" .. table.concat(preview, "\n"), "&Yes\n&No", 2)
  if choice ~= 1 then
    return -- stay in edit mode so the user can adjust
  end

  state.provider.apply_ops(ops, function(errors)
    if not state then
      return
    end
    if errors and #errors > 0 then
      vim.notify("driftwood: " .. table.concat(errors, "; "), vim.log.levels.ERROR)
    end
    exit_edit()
    reload_tree()
  end, state.cfg)
end

-- ── live filter ──────────────────────────────────────────────────────────────
-- Entered from normal tree navigation via the search key. Buffer line 0 becomes
-- an editable prompt (state 2): typing narrows the outline live to matches + their
-- ancestor path, and the first match is highlighted + previewed. <CR> jumps to it;
-- <Esc> hands the *real* cursor to the narrowed tree (state 3), where j/k/l/h and
-- <CR> behave exactly as in the unfiltered outline. A second <Esc> (in normal
-- mode) clears the filter and restores the full fold-honoring tree — folds intact,
-- since filtering never mutates node.expanded. `/` from state 3 re-opens the
-- prompt (pre-filled) to refine.

-- The "first match" tracked while typing rides only real match rows; ancestor-
-- context rows are skipped (they exist for hierarchy, not as results). Empty-query
-- rows carry no is_context flag and so all count.
local function is_result(row)
  return row and not row.is_context
end

-- First result row index at/after `from` in direction `dir`, or nil.
local function scan_result(from, dir)
  local i = from
  while state.rows[i] do
    if is_result(state.rows[i]) then
      return i
    end
    i = i + dir
  end
  return nil
end

-- Drop the prompt's insert-mode maps and autocommands (leaving the typing state).
local function search_teardown()
  for _, id in ipairs(state.search_aucmds or {}) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  state.search_aucmds = nil
  for _, lhs in ipairs(state.search_maps or {}) do
    pcall(vim.keymap.del, "i", lhs, { buffer = state.buf })
  end
  state.search_maps = nil
end

-- Re-run the filter from the prompt text (line 0) after an edit, tracking the
-- first match for the highlight/preview. Guarded on the query actually changing so
-- our own tree rewrites can't feed back into a loop.
local function search_update()
  if not typing() then
    return
  end
  local q = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
  if q == state.filter.query then
    return
  end
  state.filter.query = q
  render_rows(q, true) -- keep line 0 (the user is typing it)
  state.filter.sel = scan_result(1, 1) or 1
  paint_selection()
  local sel = state.rows[state.filter.sel]
  if follow_on() and sel then
    follow_preview(sel.node)
  end
end

-- <CR> while typing: jump straight to the first match (commit). No-op with no
-- matches, leaving the user in the prompt to keep editing.
local function search_accept()
  if not typing() then
    return
  end
  local row = state.rows[state.filter.sel]
  if not row or not is_result(row) then
    return
  end
  vim.cmd("stopinsert")
  search_teardown()
  state.filter.typing = false
  local jump = state.provider.actions and state.provider.actions.jump
  if jump then
    jump({ node = row.node, origin_win = state.origin_win, close = M.close })
  else
    M.close(false)
  end
end

-- <Esc> while typing: hand the real cursor to the tree. With matches, keep the
-- filter and browse the narrowed outline (state 3), landing on the first match.
-- With an empty query, fall back to the plain unfiltered tree (state 1).
local function search_handoff()
  if not typing() then
    return
  end
  local sel = state.rows[state.filter.sel]
  vim.cmd("stopinsert")
  search_teardown()
  state.filter.typing = false
  vim.wo[state.win].cursorline = true
  render() -- drops modifiable, repaints the bar as static query (or the idle hint)
  if state.filter.query ~= "" and sel then
    move_cursor_to_node(sel.node)
  else
    local last = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { math.min(2, last), 0 })
  end
  if follow_on() then
    local row = current_row()
    if row then
      follow_preview(row.node)
    end
  end
end

-- <Esc> while browsing a filtered tree (state 3): clear the filter and restore the
-- full fold-honoring tree, landing on the symbol under the cursor (climbing to its
-- nearest visible ancestor if it was a context-only row).
local function search_clear()
  local row = current_row()
  local node = row and row.node
  state.filter.query = ""
  state.filter.sel = 1
  render()
  if node then
    move_cursor_to_node(node)
  else
    local last = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { math.min(2, last), 0 })
  end
  if follow_on() then
    local r = current_row()
    if r then
      follow_preview(r.node)
    end
  end
end

-- Open the editable prompt (state 1 or 3 → 2). Keeps the existing query so `/`
-- from the filtered state refines it; starts insert mode with the caret at the end
-- of the (possibly pre-filled) query. `seed` (e.g. the provider's kind sigil) is
-- prepended so a dedicated key can open the prompt straight in that mode — skipped
-- when the query already starts with it, so refining doesn't stack sigils.
local function search_enter(seed)
  local search = state.cfg.search
  if not (search and search.enabled) or typing() or editing() then
    return
  end
  if seed and seed ~= "" and state.filter.query:sub(1, #seed) ~= seed then
    state.filter.query = seed .. state.filter.query
  end
  state.filter.typing = true
  vim.wo[state.win].cursorline = false -- caret parks on the bar; first match is its own hl
  render() -- redraw bar as a prompt + the (possibly pre-filled) query on line 0
  state.filter.sel = scan_result(1, 1) or 1
  paint_selection()

  local keys = search.keys or {}
  state.search_maps = {}
  local function imap(spec, fn)
    if spec == nil then
      return
    end
    if type(spec) == "string" then
      spec = { spec }
    end
    for _, lhs in ipairs(spec) do
      vim.keymap.set("i", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
      state.search_maps[#state.search_maps + 1] = lhs
    end
  end
  imap(keys.accept, search_accept)
  imap(keys.abandon, search_handoff)

  state.search_aucmds = {
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
      buffer = state.buf,
      callback = search_update,
    }),
    -- Pin the caret to the prompt line so edits can't stray into the tree.
    vim.api.nvim_create_autocmd("CursorMovedI", {
      buffer = state.buf,
      callback = function()
        if typing() and vim.api.nvim_win_get_cursor(state.win)[1] ~= 1 then
          local q = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
          vim.api.nvim_win_set_cursor(state.win, { 1, #q })
        end
      end,
    }),
  }

  vim.api.nvim_win_set_cursor(state.win, { 1, #state.filter.query })
  vim.cmd("startinsert!")
  if follow_on() and state.rows[state.filter.sel] then
    follow_preview(state.rows[state.filter.sel].node)
  end
end

-- ── keymaps ──────────────────────────────────────────────────────────────────

-- Resolve an action name to a keymap callback. Generic tree actions live in the
-- `actions` table above; anything else is looked up on the active provider and
-- invoked with a context { node, origin_win, close } describing the current row.
local function resolve_action(provider, action)
  if actions[action] then
    return actions[action]
  end
  local pa = provider.actions and provider.actions[action]
  if pa then
    return function()
      local row = current_row()
      if not row then
        return
      end
      pa({ node = row.node, origin_win = state.origin_win, close = M.close })
    end
  end
  return nil
end

local function set_keys(buf, cfg, provider)
  local function map(keys, fn)
    if type(keys) == "string" then
      keys = { keys }
    end
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
    end
  end
  for action, keys in pairs(cfg.keys) do
    local fn = resolve_action(provider, action)
    if fn then
      map(keys, fn)
    end
  end
end

-- ── layout switching ─────────────────────────────────────────────────────────

-- Move the active float to `layout`: remember it for the session, re-render
-- against the cached tree (no re-fetch — render() re-fits geometry and lets the
-- provider emit its per-layout content), and keep the cursor on the same node.
local function switch_layout(layout)
  if not state or editing() or state.cfg.window.layout == layout then
    return
  end
  if not state.cfg.window.layouts[layout] then
    return
  end
  state.cfg.window.layout = layout
  last_layout[state.provider.name] = layout
  local row = current_row()
  render()
  if row then
    move_cursor_to_node(row.node)
  end
end

-- Bind the global layout_keys (H/J/K/L/M) inside the float. Only layouts that
-- exist in the resolved geometry are bound.
local function set_layout_keys(buf, cfg)
  for layout, keys in pairs(cfg.layout_keys or {}) do
    if cfg.window.layouts[layout] then
      if type(keys) == "string" then
        keys = { keys }
      end
      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, function()
          switch_layout(layout)
        end, { buffer = buf, nowait = true, silent = true })
      end
    end
  end
end

-- ── loading state (spinner while the provider fetches) ───────────────────────
-- The float opens immediately, before the provider's (async) fetch resolves, so
-- it never blocks on slow LSP servers. Until roots arrive it shows an animated
-- braille spinner; `token` guards the async callback so a fetch that resolves
-- after its window was closed (or replaced by a newer open) is ignored.

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_MS = 80
-- Monotonic open counter; each open_loading claims the next value as its token.
local open_seq = 0

local function stop_spinner()
  if state and state.spin_timer then
    pcall(vim.fn.timer_stop, state.spin_timer)
    state.spin_timer = nil
  end
end

-- Write a single status line (the spinner or a message) as the float's only
-- content, highlight it, and re-fit the window. Bypasses the tree/bar machinery
-- entirely — during loading there are no rows, no filter, no pins.
local function render_status(line, spans)
  state.rendering = true
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { line })
  vim.bo[state.buf].modifiable = false
  state.rendering = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, s in ipairs(spans or {}) do
    add_hl(0, s[1], s[2], s[3]) -- status text lives on buffer line 0
  end
  local cw, ch = content_dims({ line })
  local geo = window.compute_geometry(state.cfg, cw, ch)
  vim.api.nvim_win_set_config(state.win, window.win_config(geo, state.cfg))
end

-- The current spinner frame as line text + highlight spans (glyph accented, label
-- dimmed). Braille glyphs are 3 bytes, so the spans are byte-accurate.
local function loading_line()
  local sp = SPINNER[state.spin_frame]
  local text = " " .. sp .. " Loading…"
  return text, { { 1, 1 + #sp, "Special" }, { 1 + #sp, #text, "Comment" } }
end

-- Timer tick: advance one frame and repaint. Stands down once populate/close has
-- cleared the loading flag (the timer is stopped there too; this is belt-and-braces).
local function spin_tick()
  if not (state and state.loading) then
    return
  end
  state.spin_frame = state.spin_frame % #SPINNER + 1
  render_status(loading_line())
end

-- ── public API ────────────────────────────────────────────────────────────────

function M.is_open()
  return state ~= nil and state.win and vim.api.nvim_win_is_valid(state.win)
end

-- Close the float. Always wipe the follow highlight. When `restore` is true this
-- is a cancel (q/Esc/toggle): snap the origin cursor+view back to the open-time
-- snapshot and refocus origin. `restore = false` is used by `jump` (which sets
-- its own cursor afterward) and by the WinLeave handler (which snaps back itself,
-- without refocusing, to respect the user's new focus).
function M.close(restore)
  if not state then
    return
  end
  stop_spinner()
  if typing() then
    pcall(vim.cmd, "stopinsert")
    search_teardown()
  end
  local win, origin_win = state.win, state.origin_win
  clear_follow()
  if restore then
    restore_origin_view()
  end
  state = nil
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if restore and origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end
end

-- Open the float *now*, in a loading state, before `provider.fetch` resolves.
-- Creates the buffer/window, snapshots the origin view, starts the spinner, and
-- binds only the close keys (the tree isn't there yet). Returns a token the caller
-- passes back to M.populate so a stale fetch can't fill the wrong window.
function M.open_loading(provider, cfg, origin)
  open_seq = open_seq + 1
  local token = open_seq

  -- Restore the layout the user last switched this provider to (this session).
  local sticky = last_layout[provider.name]
  if sticky and cfg.window.layouts[sticky] then
    cfg.window.layout = sticky
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "driftwood"
  -- Suppress the completion popup while filtering: the float only enters insert
  -- mode for the search prompt, and there's nothing here to complete. blink.cmp
  -- (and most engines) treat this buffer var as an off switch.
  vim.b[buf].completion = false

  -- Size the initial window to the loading line (re-fit again when rows arrive).
  local frame0 = " " .. SPINNER[1] .. " Loading…"
  local cw, ch = content_dims({ frame0 })
  local geo = window.compute_geometry(cfg, cw, ch)

  local win = vim.api.nvim_open_win(buf, true, window.win_config(geo, cfg))
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  -- Snapshot the origin window so follow-mode browsing can be undone on cancel.
  local follow_enabled = cfg.follow and cfg.follow.enabled
  local origin_buf = vim.api.nvim_win_get_buf(origin.win)
  local origin_view
  if follow_enabled and vim.api.nvim_win_is_valid(origin.win) then
    origin_view = vim.api.nvim_win_call(origin.win, function()
      return vim.fn.winsaveview()
    end)
  end

  state = {
    win = win,
    buf = buf,
    cfg = cfg,
    provider = provider,
    roots = nil, -- filled by M.populate when fetch resolves
    rows = {},
    origin = origin, -- kept so populate can place the cursor at the origin symbol
    origin_win = origin.win,
    origin_buf = origin_buf,
    origin_view = origin_view,
    origin_path = vim.api.nvim_buf_get_name(origin_buf),
    -- On-disk pin store key: provider override (files: tree root) or the origin file.
    pin_scope = provider.pin_scope and provider.pin_scope(cfg, origin)
      or vim.api.nvim_buf_get_name(origin_buf),
    -- Session fold-level key: provider override (files: tree root) or the origin file.
    fold_scope = provider.fold_scope and provider.fold_scope(cfg, origin)
      or vim.api.nvim_buf_get_name(origin_buf),
    follow_node = nil,
    edit = nil,
    filter = { query = "", sel = 1, typing = false },
    pinned = nil,
    pin_num = nil,
    pin_bynum = nil,
    badge_w = 0,
    loading = true,
    token = token,
    spin_frame = 1,
  }

  render_status(loading_line())

  -- Close keys work immediately, so the float can be dismissed mid-load. The full
  -- keymap (navigation, pins, search, layout) is wired in M.populate once rows exist.
  local close_keys = cfg.keys.close
  if type(close_keys) == "string" then
    close_keys = { close_keys }
  end
  for _, key in ipairs(close_keys or {}) do
    vim.keymap.set("n", key, function()
      M.close(true)
    end, { buffer = buf, nowait = true, silent = true })
  end

  -- Close when the float loses focus, even mid-load. Snap the origin view back
  -- first (without refocusing — the user chose a new window).
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      restore_origin_view()
      M.close(false)
    end,
  })

  state.spin_timer = vim.fn.timer_start(SPINNER_MS, spin_tick, { ["repeat"] = -1 })
  return token
end

-- Fill the loading float with the fetched `roots` (or a "No symbols" message when
-- `roots` is nil), then wire up the full keymap and place the cursor. No-ops unless
-- `token` still matches the open float — guarding against a fetch that resolved
-- after its window was closed or replaced by a newer open.
function M.populate(token, roots)
  if not (state and state.token == token and state.loading) then
    return
  end
  stop_spinner()
  state.loading = false

  -- No symbols (or no capable LSP client): keep the float open with a message; the
  -- close keys are already bound, and there's no tree to navigate.
  if not roots then
    render_status(" No symbols", { { 0, #" No symbols", "Comment" } })
    return
  end

  local provider, cfg, origin, buf, win = state.provider, state.cfg, state.origin, state.buf, state.win
  local follow_enabled = cfg.follow and cfg.follow.enabled

  tree.prepare(roots, cfg.initial_depth)
  state.roots = roots

  -- Resolve the fold level: the session-sticky level (last set via </>, zM/zR) for
  -- *this file* if any, else the configured initial depth (a number is that level;
  -- "all"/true/nil means fully open == max_level). Then apply it to the tree so the
  -- folds match the restored meter — overriding tree.prepare's initial pass.
  state.max_level = tree.max_level(roots)
  local sticky = last_fold_level[fold_key()]
  local lvl
  if sticky ~= nil then
    lvl = sticky
  else
    local id = cfg.initial_depth
    lvl = type(id) == "number" and id or state.max_level
  end
  state.fold_level = math.max(0, math.min(lvl, state.max_level))
  tree.set_expanded_depth(roots, state.fold_level)

  refresh_pins() -- load + prune the file's pins before the first render

  -- Focus target: the node the open should land on. A provider with `focus` (files)
  -- resolves the origin buffer's own file; reveal the path down to it so it's visible
  -- even under a collapsed fold level. Symbols has no `focus` and instead uses
  -- follow's find_enclosing below.
  local focus_target
  if provider.focus then
    focus_target = provider.focus(roots, {
      win = origin.win,
      pos = origin.pos,
      buf = state.origin_buf,
      path = state.origin_path,
    }, cfg)
    if focus_target then
      reveal_ancestors(focus_target)
    end
  end

  render()
  set_keys(buf, cfg, provider)
  set_layout_keys(buf, cfg)

  -- Pins: `p` toggles the row's pin; the jump_keys (1..9) jump to a pin by number.
  if pins_enabled() then
    if cfg.pins.key then
      vim.keymap.set("n", cfg.pins.key, pin_toggle, { buffer = buf, nowait = true, silent = true })
    end
    for _, k in ipairs(cfg.pins.jump_keys or {}) do
      local n = tonumber(k)
      if n then
        vim.keymap.set("n", k, function()
          pin_jump(n)
        end, { buffer = buf, nowait = true, silent = true })
      end
    end
  end

  if cfg.search and cfg.search.enabled then
    -- `/` opens the editable prompt (state 1/3 → 2).
    if cfg.search.key then
      vim.keymap.set("n", cfg.search.key, search_enter, {
        buffer = buf,
        nowait = true,
        silent = true,
      })
    end
    -- The provider's kind sigil (e.g. `@`) opens the same prompt pre-seeded with the
    -- sigil, so a user lands straight in kind mode without typing `/` first.
    if provider.kind_sigil then
      vim.keymap.set("n", provider.kind_sigil, function()
        search_enter(provider.kind_sigil)
      end, { buffer = buf, nowait = true, silent = true })
    end
    -- Normal-mode <Esc> clears an applied filter (state 3 → 1); it does not close
    -- the float (only q and ; do, bound by set_keys). With no filter it's a no-op.
    vim.keymap.set("n", "<Esc>", function()
      if filtering() then
        search_clear()
      end
    end, { buffer = buf, nowait = true, silent = true })
  end

  -- Follow-mode: preview the hovered node on every cursor move within the float.
  -- While the prompt is open (state 2) the caret sits on the bar and follow is
  -- driven by the live query instead, so this normal-mode handler stands down.
  if follow_enabled then
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = buf,
      callback = function()
        if not state or typing() then
          return
        end
        local row = current_row()
        if row then
          follow_preview(row.node)
        end
      end,
    })
  end

  -- Land the cursor on the focus target (files: the current file, revealed above),
  -- else follow's enclosing symbol. find_enclosing indexes the origin buffer via
  -- node.range, which only buffer-position providers (symbols) have — gate it on
  -- follow so range-less providers without a focus hit just land on the first row.
  local landing = focus_target
    or (follow_enabled and tree.find_enclosing(roots, origin.pos[1] - 1, origin.pos[2]))
  if landing then
    move_cursor_to_node(landing)
  else
    local last = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(win, { math.min(2, last), 0 })
  end

  -- Preview the initial selection immediately (CursorMoved may not have fired for
  -- the programmatic placement above).
  if follow_enabled then
    local row = current_row()
    if row then
      follow_preview(row.node)
    end
  end
end

return M
