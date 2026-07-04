-- driftwood.ui — the floating window: create/size/position, render rows with
-- highlights, and wire keymaps to actions. All Neovim-coupled code lives here.

local tree = require("driftwood.tree")
local window = require("driftwood.window")

local M = {}
local ns = vim.api.nvim_create_namespace("driftwood")

-- state = { win, buf, cfg, provider, roots, rows, origin_win }
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

-- Recompute rows from fold state, rewrite the buffer, reapply highlights, and
-- re-fit the window to the active layout (only "fit" dimensions track content).
local function render()
  state.rows = tree.flatten(state.roots)
  local lines, spans = {}, {}
  for i, row in ipairs(state.rows) do
    lines[i], spans[i] = state.provider.render(row, state.cfg, state.cfg.window.layout)
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, row_spans in ipairs(spans) do
    for _, s in ipairs(row_spans) do
      add_hl(i - 1, s[1], s[2], s[3])
    end
  end

  local cw, ch = content_dims(lines)
  local geo = window.compute_geometry(state.cfg, cw, ch)
  vim.api.nvim_win_set_config(state.win, window.win_config(geo, state.cfg))
end

-- Move the cursor to `node`'s row; if it's not visible, climb to the nearest
-- visible ancestor. Falls back to the first row.
local function move_cursor_to_node(node)
  while node do
    for i, row in ipairs(state.rows) do
      if row.node == node then
        vim.api.nvim_win_set_cursor(state.win, { i, 0 })
        return
      end
    end
    node = node.parent
  end
  vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
end

local function current_row()
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.rows[line], line
end

-- ── actions (the rebindable behavior surface) ────────────────────────────────

local actions = {}

function actions.down()
  local _, line = current_row()
  if line < #state.rows then
    vim.api.nvim_win_set_cursor(state.win, { line + 1, 0 })
  end
end

function actions.up()
  local _, line = current_row()
  if line > 1 then
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

-- Close the float. When `restore` is true, refocus the origin window (the
-- origin cursor was never moved while browsing, so nothing else to restore).
function M.close(restore)
  if not state then
    return
  end
  local win, origin_win = state.win, state.origin_win
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

  state = {
    win = win,
    buf = buf,
    cfg = cfg,
    provider = provider,
    roots = roots,
    rows = rows,
    origin_win = origin.win,
  }

  render()
  set_keys(buf, cfg, provider)
  set_layout_keys(buf, cfg)

  local enclosing = tree.find_enclosing(roots, origin.pos[1] - 1, origin.pos[2])
  if enclosing then
    move_cursor_to_node(enclosing)
  else
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end

  -- Close when the float loses focus (e.g. the user clicks another window).
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      M.close(false)
    end,
  })
end

return M
