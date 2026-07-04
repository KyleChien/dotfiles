-- symboltree.ui — the floating window: create/size/position, render rows with
-- highlights, and wire keymaps to actions. All Neovim-coupled code lives here.

local tree = require("symboltree.tree")

local M = {}
local ns = vim.api.nvim_create_namespace("symboltree")

-- state = { win, buf, cfg, roots, rows, origin_win }
local state = nil

-- ── rendering ──────────────────────────────────────────────────────────────

-- Returns the line text and byte-column segments for a row.
local function build_line(row, cfg)
  local indent = string.rep("  ", row.depth)
  local chevron
  if row.has_children then
    chevron = row.node.expanded and cfg.chevron.expanded or cfg.chevron.collapsed
  else
    chevron = " "
  end
  local icon = cfg.icons[row.node.kind] or cfg.icons.default
  local prefix = indent .. chevron .. " "
  local icon_part = icon .. " "
  local text = prefix .. icon_part .. row.node.name
  return text, {
    chevron = { #indent, #indent + #chevron },
    icon = { #prefix, #prefix + #icon },
    name = { #prefix + #icon_part, #text },
  }
end

local function add_hl(line, span, group)
  vim.api.nvim_buf_set_extmark(state.buf, ns, line, span[1], {
    end_row = line,
    end_col = span[2],
    hl_group = group,
  })
end

-- ── window geometry ──────────────────────────────────────────────────────────
--
-- Size values (width/height and the max_* bounds) accept:
--   integer >= 1   → absolute cells
--   float in (0,1) → fraction of the editor dimension
--   "max"          → fill the usable axis (editor minus border/chrome)
--   "fit"          → hug content, clamped by min_/max_ bounds (fold-reactive)

-- Longest visible row (display cells) and row count. +2 pads the width so text
-- doesn't touch the border when a dimension is "fit".
local function content_dims(lines)
  local w = 1
  for _, l in ipairs(lines) do
    w = math.max(w, vim.fn.strdisplaywidth(l))
  end
  return w + 2, #lines
end

-- Rows consumed by the tabline (0 or 1).
local function tabline_rows()
  local st = vim.o.showtabline
  if st == 2 or (st == 1 and #vim.api.nvim_list_tabpages() > 1) then
    return 1
  end
  return 0
end

-- Inner extents (excluding border) a float may occupy, plus the tabline offset.
local function usable_area()
  local tab = tabline_rows()
  local avail_w = math.max(1, vim.o.columns - 2)
  local avail_h = math.max(1, vim.o.lines - vim.o.cmdheight - tab - 2)
  return avail_w, avail_h, tab
end

-- Resolve a concrete extent (number or "max") into cells for an axis.
local function resolve_extent(value, axis, avail)
  if value == "max" or value == "maximized" then
    return avail
  end
  if type(value) == "number" then
    local base = axis == "width" and vim.o.columns or vim.o.lines
    local cells = (value > 0 and value < 1) and math.floor(base * value) or math.floor(value)
    return math.max(1, math.min(cells, avail))
  end
  return avail
end

-- Resolve a dimension spec (including "fit") into cells.
local function resolve_dim(spec, lcfg, axis, content_len, avail)
  if spec ~= "fit" then
    return resolve_extent(spec, axis, avail)
  end
  local min_key = axis == "width" and "min_width" or "min_height"
  local max_key = axis == "width" and "max_width" or "max_height"
  local mn = lcfg[min_key] or 1
  local mx = resolve_extent(lcfg[max_key] or "max", axis, avail)
  return math.max(1, math.min(math.max(mn, math.min(content_len, mx)), avail))
end

-- Compute the full floating-window geometry for the active layout. Border is
-- drawn outside the returned row/col/width/height, so valid content corners are
-- inset by one cell from every editor edge.
local function compute_geometry(cfg, content_w, content_h)
  local win = cfg.window
  local avail_w, avail_h, tab = usable_area()

  if type(win.layout) == "function" then
    return win.layout({
      columns = vim.o.columns,
      lines = vim.o.lines,
      avail_w = avail_w,
      avail_h = avail_h,
      content_w = content_w,
      content_h = content_h,
    })
  end

  local layout = win.layout
  local lcfg = (win.layouts and win.layouts[layout]) or {}
  local W = resolve_dim(lcfg.width or "fit", lcfg, "width", content_w, avail_w)
  local H = resolve_dim(lcfg.height or "fit", lcfg, "height", content_h, avail_h)

  local col_min, col_max = 1, vim.o.columns - 1 - W
  local row_min, row_max = tab + 1, vim.o.lines - vim.o.cmdheight - 1 - H
  local center_col = math.floor((col_min + col_max) / 2)
  local center_row = math.floor((row_min + row_max) / 2)

  local row, col
  if layout == "left" then
    col, row = col_min, center_row
  elseif layout == "right" then
    col, row = col_max, center_row
  elseif layout == "top" then
    row, col = row_min, center_col
  elseif layout == "bottom" then
    row, col = row_max, center_col
  else -- center (and any unknown name)
    row, col = center_row, center_col
  end

  return {
    relative = "editor",
    row = math.max(row_min, math.min(row, row_max)),
    col = math.max(col_min, math.min(col, col_max)),
    width = W,
    height = H,
  }
end

-- Build the nvim_open_win / nvim_win_set_config table from a geometry.
local function win_config(geo, cfg)
  local c = {
    relative = geo.relative or "editor",
    row = geo.row,
    col = geo.col,
    width = geo.width,
    height = geo.height,
    style = "minimal",
    border = cfg.window.border,
    title = cfg.window.title,
    title_pos = "center",
    zindex = 60,
  }
  if geo.anchor then
    c.anchor = geo.anchor
  end
  return c
end

-- Recompute rows from fold state, rewrite the buffer, reapply highlights, and
-- re-fit the window to the active layout (only "fit" dimensions track content).
local function render()
  state.rows = tree.flatten(state.roots)
  local lines, segs = {}, {}
  for i, row in ipairs(state.rows) do
    lines[i], segs[i] = build_line(row, state.cfg)
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, row in ipairs(state.rows) do
    local seg = segs[i]
    if row.has_children then
      add_hl(i - 1, seg.chevron, state.cfg.hl.chevron)
    end
    local group = state.cfg.kind_hl[row.node.kind] or state.cfg.hl.name
    add_hl(i - 1, seg.icon, group)
    add_hl(i - 1, seg.name, group)
  end

  local cw, ch = content_dims(lines)
  vim.api.nvim_win_set_config(state.win, win_config(compute_geometry(state.cfg, cw, ch), state.cfg))
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

function actions.jump()
  local row = current_row()
  if not row then
    return
  end
  local target = row.node.selection_range.start
  local win = state.origin_win
  M.close(false)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { target.line + 1, target.character })
    vim.cmd("normal! zz")
  end
end

function actions.close()
  M.close(true)
end

-- ── keymaps ──────────────────────────────────────────────────────────────────

local function set_keys(buf, cfg)
  local function map(keys, action)
    if type(keys) == "string" then
      keys = { keys }
    end
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, actions[action], { buffer = buf, nowait = true, silent = true })
    end
  end
  for action, keys in pairs(cfg.keys) do
    if actions[action] then
      map(keys, action)
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

-- Open the float for `roots`, focus it, and place the cursor on the symbol that
-- encloses `origin.pos` (a 1-based {line, col} from nvim_win_get_cursor).
function M.open(roots, cfg, origin)
  tree.prepare(roots, cfg.initial_depth)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "symboltree"

  local rows = tree.flatten(roots)
  local lines = {}
  for i, row in ipairs(rows) do
    lines[i] = build_line(row, cfg)
  end
  local cw, ch = content_dims(lines)
  local geo = compute_geometry(cfg, cw, ch)

  local win = vim.api.nvim_open_win(buf, true, win_config(geo, cfg))
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  state = {
    win = win,
    buf = buf,
    cfg = cfg,
    roots = roots,
    rows = rows,
    origin_win = origin.win,
  }

  render()
  set_keys(buf, cfg)

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
