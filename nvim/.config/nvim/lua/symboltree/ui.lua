-- symboltree.ui — the floating window: create/size/position, render rows with
-- highlights, and wire keymaps to actions. All Neovim-coupled code lives here.

local tree = require("symboltree.tree")

local M = {}
local ns = vim.api.nvim_create_namespace("symboltree")

-- state = { win, buf, cfg, roots, rows, base_win, origin_win }
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

-- Recompute rows from fold state, rewrite the buffer, reapply highlights, and
-- resize the window's height to fit (width/position stay fixed from open).
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

  local max_h = math.floor(vim.o.lines * state.cfg.window.max_height_ratio)
  local height = math.max(1, math.min(#lines, max_h))
  vim.api.nvim_win_set_config(state.win, vim.tbl_extend("force", state.base_win, { height = height }))
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

-- ── window geometry ──────────────────────────────────────────────────────────

local function compute_dims(lines, cfg)
  local width = cfg.window.min_width
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 2, cfg.window.max_width)
  local max_h = math.floor(vim.o.lines * cfg.window.max_height_ratio)
  local height = math.max(1, math.min(#lines, max_h))
  return width, height
end

local function compute_position(width, height, cfg)
  local pos = cfg.window.position
  if type(pos) == "function" then
    return pos({ width = width, height = height })
  end
  local cols, lns = vim.o.columns, vim.o.lines
  local presets = {
    center = { relative = "editor", row = math.floor((lns - height) / 2 - 1), col = math.floor((cols - width) / 2) },
    topleft = { relative = "editor", row = 1, col = 2 },
    topright = { relative = "editor", row = 1, col = cols - width - 4 },
    botleft = { relative = "editor", row = lns - height - 4, col = 2 },
    botright = { relative = "editor", row = lns - height - 4, col = cols - width - 4 },
    cursor = { relative = "cursor", row = 1, col = 0 },
  }
  return presets[pos] or presets.center
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
  tree.prepare(roots)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "symboltree"

  local rows = tree.flatten(roots)
  local lines = {}
  for i, row in ipairs(rows) do
    lines[i] = build_line(row, cfg)
  end
  local width, height = compute_dims(lines, cfg)
  local p = compute_position(width, height, cfg)

  local base = {
    relative = p.relative,
    row = p.row,
    col = p.col,
    width = width,
    height = height,
    style = "minimal",
    border = cfg.window.border,
    title = cfg.window.title,
    title_pos = "center",
    zindex = 60,
  }
  if p.anchor then
    base.anchor = p.anchor
  end

  local win = vim.api.nvim_open_win(buf, true, base)
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
    base_win = base,
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
