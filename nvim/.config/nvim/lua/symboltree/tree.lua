-- symboltree.tree — pure tree logic (no Neovim window calls).
-- Consumes normalized nodes, produces renderable rows and fold transitions.
--
-- Node shape (from symboltree.lsp):
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
-- Each row: { node, depth, has_children }
function M.flatten(roots)
  local rows = {}
  local function walk(nodes, depth)
    for _, node in ipairs(nodes) do
      local has_children = node.children ~= nil and #node.children > 0
      rows[#rows + 1] = { node = node, depth = depth, has_children = has_children }
      if has_children and node.expanded then
        walk(node.children, depth + 1)
      end
    end
  end
  walk(roots, 0)
  return rows
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
