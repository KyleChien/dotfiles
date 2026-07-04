-- driftwood.ui — the floating window: create/size/position, render rows with
-- highlights, and wire keymaps to actions. All Neovim-coupled code lives here.

local tree = require("driftwood.tree")
local window = require("driftwood.window")

local M = {}
local ns = vim.api.nvim_create_namespace("driftwood")
-- Separate namespace for the follow-mode highlight painted in the *origin*
-- buffer (the outline lives in `ns` on the float buffer).
local ns_follow = vim.api.nvim_create_namespace("driftwood_follow")
-- The search bar's inline virtual text (prompt glyph / idle hint) on line 0.
local ns_bar = vim.api.nvim_create_namespace("driftwood_bar")
-- The picker's selected-row highlight. Its own namespace so the selection can be
-- repainted (on <C-n>/<C-p>) without touching the content highlights in `ns`.
local ns_sel = vim.api.nvim_create_namespace("driftwood_sel")

-- The float reserves buffer line 0 for the search bar; the tree occupies lines
-- 1..N. So tree row i (1-based, into state.rows) lives on 0-based buffer line i,
-- i.e. cursor line i + 1. All the row<->line math below honors that offset.
--
-- state = { win, buf, cfg, provider, roots, rows, origin_win, origin_buf,
--           origin_view, follow_node,
--           filter = { active, query, sel }, picker_aucmds, rendering }
local state = nil

-- Sticky-in-session layout: provider name -> last layout the user switched to.
-- Cleared on nvim restart; never written to disk.
local last_layout = {}

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

-- Is the live filter currently accepting input?
local function picker_active()
  return state and state.filter and state.filter.active
end

-- The rows to display: filtered when a non-empty query is active, else the full
-- fold-honoring tree. Filtering never mutates node.expanded, so clearing the
-- query restores the exact prior folds.
local function compute_rows()
  if picker_active() and state.filter.query ~= "" then
    return tree.flatten_filtered(state.roots, state.filter.query)
  end
  return tree.flatten(state.roots)
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
  if picker_active() then
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

-- Paint the picker's selected-row highlight (whole line) over the selected tree
-- row. No-op when not filtering or when there are no matches.
local function paint_selection()
  vim.api.nvim_buf_clear_namespace(state.buf, ns_sel, 0, -1)
  if not picker_active() then
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
  if picker_active() then
    return vim.fn.strdisplaywidth((search.prompt or "") .. state.filter.query)
  end
  return vim.fn.strdisplaywidth(search.hint or "")
end

-- Re-fit the window to the given lines (plus the bar's virtual width).
local function refit(lines)
  local cw, ch = content_dims(lines)
  cw = math.max(cw, bar_width() + 2)
  local geo = window.compute_geometry(state.cfg, cw, ch)
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
  local no_match = picker_active() and state.filter.query ~= "" and #state.rows == 0
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
  vim.bo[state.buf].modifiable = picker_active() and true or false
  state.rendering = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, row_spans in ipairs(spans) do
    for _, s in ipairs(row_spans) do
      add_hl(i, s[1], s[2], s[3]) -- tree row i (1-based) -> 0-based buffer line i
    end
  end
  paint_selection()

  local measured = { bar_text }
  vim.list_extend(measured, tree_lines)
  refit(measured)
end

-- Full render: rewrite line 0 (bar) and the tree, and repaint the bar's virtual
-- text. Used on open, layout switch, and entering/leaving the picker.
local function render()
  render_rows(picker_active() and state.filter.query or "", false)
  paint_bar()
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

-- ── actions (the rebindable behavior surface) ────────────────────────────────

local actions = {}

function actions.down()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  if line - 1 < #state.rows then -- a next tree row exists
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
  local row = current_row()
  if row and row.has_children and not row.node.expanded then
    row.node.expanded = true
    render()
    move_cursor_to_node(row.node)
  end
end

function actions.collapse()
  local row = current_row()
  if not row then
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

function actions.expand_all()
  local row = current_row()
  tree.set_expanded_all(state.roots, true)
  render()
  if row then
    move_cursor_to_node(row.node)
  end
end

function actions.collapse_all()
  local row = current_row()
  tree.set_expanded_all(state.roots, false)
  render()
  if row then
    move_cursor_to_node(row.node)
  end
end

function actions.close()
  M.close(true)
end

-- ── live filter (picker mode) ────────────────────────────────────────────────
-- Entered from normal tree navigation via the search key. Buffer line 0 becomes
-- an editable prompt: typing filters the outline to matches + their ancestor
-- path; the selection is moved with next/prev keys and previewed via follow mode.
-- accept jumps to the selected symbol; abandon restores the full fold-honoring
-- tree (folds intact — filtering never mutates them).

-- Selection rides only match rows; ancestor-context rows are skipped (they exist
-- for hierarchy, not as results). Empty-query rows carry no is_context flag and
-- so all count as selectable.
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

-- Move the selection to the next/prev result (dir = +1/-1). No wrap.
local function picker_move(dir)
  if not picker_active() or #state.rows == 0 then
    return
  end
  local i = scan_result(state.filter.sel + dir, dir)
  if i then
    state.filter.sel = i
    paint_selection()
    if follow_on() then
      follow_preview(state.rows[i].node)
    end
  end
end

-- Re-run the filter from the prompt text (line 0) after an edit. Guarded on the
-- query actually changing so our own tree rewrites can't feed back into a loop.
local function picker_update()
  if not picker_active() then
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

-- Jump to the selected match (commit), closing the float.
local function picker_accept()
  local row = state.rows[state.filter.sel]
  if not row then
    return
  end
  vim.cmd("stopinsert")
  local jump = state.provider.actions and state.provider.actions.jump
  if jump then
    jump({ node = row.node, origin_win = state.origin_win, close = M.close })
  else
    M.close(false)
  end
end

-- Drop the picker's insert-mode maps and autocommands.
local function picker_teardown()
  for _, id in ipairs(state.picker_aucmds or {}) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  state.picker_aucmds = nil
  for _, lhs in ipairs(state.picker_maps or {}) do
    pcall(vim.keymap.del, "i", lhs, { buffer = state.buf })
  end
  state.picker_maps = nil
end

-- Leave the picker and restore the full tree, landing on the selected symbol.
local function picker_abandon()
  if not picker_active() then
    return
  end
  local sel = state.rows[state.filter.sel]
  local node = sel and sel.node
  vim.cmd("stopinsert")
  picker_teardown()
  state.filter.active = false
  state.filter.query = ""
  state.filter.sel = 1
  vim.wo[state.win].cursorline = true
  render()
  if node then
    move_cursor_to_node(node)
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

-- Enter the picker: make line 0 an editable, empty prompt and start insert mode.
local function picker_enter()
  local search = state.cfg.search
  if not (search and search.enabled) or picker_active() then
    return
  end
  state.filter.active = true
  state.filter.query = ""
  state.filter.sel = 1
  vim.wo[state.win].cursorline = false -- caret parks on the bar; selection is its own hl
  render() -- redraw bar as a prompt + full tree, with line 0 emptied

  local keys = search.keys or {}
  state.picker_maps = {}
  local function imap(spec, fn)
    if spec == nil then
      return
    end
    if type(spec) == "string" then
      spec = { spec }
    end
    for _, lhs in ipairs(spec) do
      vim.keymap.set("i", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
      state.picker_maps[#state.picker_maps + 1] = lhs
    end
  end
  imap(keys.next, function()
    picker_move(1)
  end)
  imap(keys.prev, function()
    picker_move(-1)
  end)
  imap(keys.accept, picker_accept)
  imap(keys.abandon, picker_abandon)

  state.picker_aucmds = {
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
      buffer = state.buf,
      callback = picker_update,
    }),
    -- Pin the caret to the prompt line so edits can't stray into the tree.
    vim.api.nvim_create_autocmd("CursorMovedI", {
      buffer = state.buf,
      callback = function()
        if picker_active() and vim.api.nvim_win_get_cursor(state.win)[1] ~= 1 then
          local q = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
          vim.api.nvim_win_set_cursor(state.win, { 1, #q })
        end
      end,
    }),
  }

  vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
  vim.cmd("startinsert!")
  if follow_on() and state.rows[1] then
    follow_preview(state.rows[1].node)
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
  if not state or state.cfg.window.layout == layout then
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
  if picker_active() then
    pcall(vim.cmd, "stopinsert")
    picker_teardown()
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

-- Open the float for `provider`'s `roots`, focus it, and place the cursor on the
-- node that encloses `origin.pos` (a 1-based {line, col} from nvim_win_get_cursor).
function M.open(provider, roots, cfg, origin)
  tree.prepare(roots, cfg.initial_depth)

  -- Restore the layout the user last switched this provider to (this session).
  local sticky = last_layout[provider.name]
  if sticky and cfg.window.layouts[sticky] then
    cfg.window.layout = sticky
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "driftwood"
  -- Suppress the completion popup while filtering: the float only enters insert
  -- mode for the search picker, and there's nothing here to complete. blink.cmp
  -- (and most engines) treat this buffer var as an off switch; it also frees the
  -- picker's <C-n>/<C-p>/<Up>/<Down> from blink's menu-selection keymaps.
  vim.b[buf].completion = false

  local rows = tree.flatten(roots)
  local lines = {}
  for i, row in ipairs(rows) do
    lines[i] = provider.render(row, cfg, cfg.window.layout)
  end
  local cw, ch = content_dims(lines)
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
    roots = roots,
    rows = rows,
    origin_win = origin.win,
    origin_buf = origin_buf,
    origin_view = origin_view,
    follow_node = nil,
    filter = { active = false, query = "", sel = 1 },
  }

  render()
  set_keys(buf, cfg, provider)
  set_layout_keys(buf, cfg)

  -- Search: bind the trigger key that enters the live-filter picker.
  if cfg.search and cfg.search.enabled and cfg.search.key then
    vim.keymap.set("n", cfg.search.key, picker_enter, {
      buffer = buf,
      nowait = true,
      silent = true,
    })
  end

  -- Follow-mode: preview the hovered node on every cursor move within the float.
  -- While the picker is active the caret sits on the bar and follow is driven by
  -- selection moves instead, so this normal-mode handler stands down.
  if follow_enabled then
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = buf,
      callback = function()
        if not state or picker_active() then
          return
        end
        local row = current_row()
        if row then
          follow_preview(row.node)
        end
      end,
    })
  end

  local enclosing = tree.find_enclosing(roots, origin.pos[1] - 1, origin.pos[2])
  if enclosing then
    move_cursor_to_node(enclosing)
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

  -- Close when the float loses focus (e.g. the user clicks another window). Snap
  -- the origin view back first (without refocusing — the user chose a new window).
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      restore_origin_view()
      M.close(false)
    end,
  })
end

return M
