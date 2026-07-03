-- symboltree.tree — pure tree logic (no Neovim window calls).
-- Consumes normalized nodes, produces renderable rows and fold transitions.
--
-- Node shape (from symboltree.lsp):
--   { name, kind, range, selection_range, children, parent?, expanded? }

local M = {}

-- Annotate the tree in place: link each node to its parent and start expanded.
function M.prepare(roots)
  local function walk(nodes, parent)
    for _, node in ipairs(nodes) do
      node.parent = parent
      node.expanded = true
      if node.children then
        walk(node.children, node)
      end
    end
  end
  walk(roots, nil)
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
