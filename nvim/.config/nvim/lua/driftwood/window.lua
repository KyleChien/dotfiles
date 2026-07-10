-- driftwood.window — floating-window geometry: resolve a layout spec into a
-- concrete row/col/width/height and build the nvim_open_win config. Pure
-- geometry — no buffer, no state, no rendering. Reads only vim.o and the passed
-- config, so it can be exercised in isolation.
--
-- Size values (width/height and the max_* bounds) accept:
--   integer >= 1   → absolute cells
--   float in (0,1) → fraction of the editor dimension
--   "max"          → fill the usable axis (editor minus border/chrome)
--   "fit"          → hug content, clamped by min_/max_ bounds (fold-reactive)

local M = {}

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
function M.compute_geometry(cfg, content_w, content_h)
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
function M.win_config(geo, cfg)
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
  -- A caller can override the border title per-apply (e.g. the shell appends its
  -- live fold-level meter). Accepts a string or nvim's [text, hl] chunk list.
  if geo.title ~= nil then
    c.title = geo.title
  end
  return c
end

return M
