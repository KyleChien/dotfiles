-- driftwood.tree — pure tree logic (no Neovim window calls).
-- Consumes normalized nodes, produces renderable rows and fold transitions.
--
-- Node shape (from a provider, e.g. driftwood.providers.symbols):
--   { name, kind, range, selection_range, children, parent?, expanded? }

local M = {}

-- Annotate the tree in place: link each node to its parent and set the initial
-- fold state. `initial_depth` is how many levels to expand — a non-negative
-- integer, or "all"/true/nil for everything. A branch at depth d is expanded
-- when d < max_depth, so `initial_depth = 0` shows only top-level symbols, `1`
-- shows their direct children, and so on.
function M.prepare(roots, initial_depth)
  local max_depth = math.huge
  if type(initial_depth) == "number" then
    max_depth = math.max(0, math.floor(initial_depth))
  end
  local function walk(nodes, parent, depth)
    for _, node in ipairs(nodes) do
      node.parent = parent
      local has_children = node.children ~= nil and #node.children > 0
      node.expanded = has_children and depth < max_depth
      if has_children then
        walk(node.children, node, depth + 1)
      end
    end
  end
  walk(roots, nil, 0)
end

-- Flatten the tree into the list of currently-visible rows, honoring fold state.
-- Each row: { node, depth, has_children, expanded }
--   expanded → whether the chevron should read as open (drives rendering; under
--   a filter it can differ from node.expanded, which filtering never mutates).
function M.flatten(roots)
  local rows = {}
  local function walk(nodes, depth)
    for _, node in ipairs(nodes) do
      local has_children = node.children ~= nil and #node.children > 0
      rows[#rows + 1] = {
        node = node,
        depth = depth,
        has_children = has_children,
        expanded = has_children and node.expanded,
      }
      if has_children and node.expanded then
        walk(node.children, depth + 1)
      end
    end
  end
  walk(roots, 0)
  return rows
end

-- Filtered flatten: return only rows on a path to a match, ignoring fold state
-- (matches and their ancestors are force-shown, so the outline auto-reveals hits
-- without touching node.expanded — clearing the filter restores the exact prior
-- folds for free). Substring match on node.name with smartcase: case-insensitive
-- unless the query contains an uppercase letter.
--   Each row adds: match_span = { s, e } (0-based byte span within the name, only
--   on rows that matched themselves) and is_context = true on ancestor-only rows.
-- Returns the row list (possibly empty when nothing matches).
function M.flatten_filtered(roots, query)
  if not query or query == "" then
    return M.flatten(roots)
  end

  local ignorecase = query == query:lower()
  local needle = ignorecase and query:lower() or query
  -- byte span of `needle` in `name` (plain, no patterns), or nil.
  local function match(name)
    local hay = ignorecase and name:lower() or name
    local s = hay:find(needle, 1, true)
    if s then
      return s - 1, s - 1 + #needle
    end
    return nil
  end

  -- Build the visible rows for `nodes`. A node is kept when it matches itself or
  -- has any kept descendant; kept branches are force-shown (expanded), matched
  -- rows carry a match_span, ancestor-only rows are flagged is_context.
  local function build(nodes, depth)
    local acc = {}
    for _, node in ipairs(nodes) do
      local ms, me = match(node.name)
      local has_children = node.children ~= nil and #node.children > 0
      local child_rows = has_children and build(node.children, depth + 1) or {}
      if ms or #child_rows > 0 then
        acc[#acc + 1] = {
          node = node,
          depth = depth,
          has_children = has_children,
          expanded = #child_rows > 0, -- open only when we actually reveal children
          match_span = ms and { ms, me } or nil,
          is_context = ms == nil,
        }
        for _, r in ipairs(child_rows) do
          acc[#acc + 1] = r
        end
      end
    end
    return acc
  end
  return build(roots, 0)
end

-- Expand or collapse every branch in the tree.
function M.set_expanded_all(roots, value)
  local function walk(nodes)
    for _, node in ipairs(nodes) do
      if node.children and #node.children > 0 then
        node.expanded = value
        walk(node.children)
      end
    end
  end
  walk(roots)
end

-- Deepest node whose range contains the 0-based (line, col) position, or nil.
function M.find_enclosing(roots, line, col)
  local function contains(range)
    local s, e = range.start, range["end"]
    if line < s.line or line > e.line then
      return false
    end
    if line == s.line and col < s.character then
      return false
    end
    if line == e.line and col > e.character then
      return false
    end
    return true
  end
  local best = nil
  local function walk(nodes)
    for _, node in ipairs(nodes) do
      if contains(node.range) then
        best = node
        if node.children then
          walk(node.children)
        end
      end
    end
  end
  walk(roots)
  return best
end

return M
