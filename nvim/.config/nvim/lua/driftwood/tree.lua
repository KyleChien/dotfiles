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
--
-- `pinned` (optional node-set) force-shows pinned nodes even inside a collapsed
-- ancestor: on descending into a folded branch we keep only pinned descendants
-- plus the ancestor chain down to them (those ancestors flagged is_context, drawn
-- dimmed). The folded parent keeps its collapsed chevron yet still shows its
-- pinned child. With no pinned set this is the plain fold-honoring flatten.
function M.flatten(roots, pinned)
  -- `forced` = we're inside a collapsed branch, so only pinned nodes and the
  -- ancestors on the path to a pinned descendant may surface.
  local function walk(nodes, depth, forced)
    local acc = {}
    for _, node in ipairs(nodes) do
      local has_children = node.children ~= nil and #node.children > 0
      local is_pinned = pinned and pinned[node] or false
      -- Children are forced when we already are, or when this branch is folded.
      local child_forced = forced or (has_children and not node.expanded)
      local child_rows = has_children and walk(node.children, depth + 1, child_forced) or {}
      -- Outside a fold every node shows; inside one, only pins and their ancestors.
      local show = (not forced) or is_pinned or #child_rows > 0
      if show then
        acc[#acc + 1] = {
          node = node,
          depth = depth,
          has_children = has_children,
          expanded = has_children and node.expanded,
          is_context = (forced and not is_pinned) or nil,
        }
        for _, r in ipairs(child_rows) do
          acc[#acc + 1] = r
        end
      end
    end
    return acc
  end
  return walk(roots, 0, false)
end

-- Filtered flatten: return only rows on a path to a match, ignoring fold state
-- (matches and their ancestors are force-shown, so the outline auto-reveals hits
-- without touching node.expanded — clearing the filter restores the exact prior
-- folds for free). Matching is provider-owned: `matcher` maps a node to `false`
-- (no match) or `{ span }`, where `span` is a 0-based byte range within the name to
-- highlight (or nil for a match with nothing to underline). The generic tree stays
-- symbol-agnostic — it never inspects node.name or node.kind itself.
--   Each row adds: match_span = { s, e } (the matcher's span, only on rows that
--   matched themselves) and is_context = true on ancestor-only rows.
-- A matcher result may also carry `scope = true`: the matched node is shown with
-- its (loaded) subtree, but honoring each branch's fold state (node.expanded) — so
-- scoping respects the current fold level rather than blowing the whole subtree
-- open. The files provider uses this for `@folder` scoping; symbols never sets it.
-- Returns the row list (possibly empty when nothing matches).
function M.flatten_filtered(roots, matcher)
  if not matcher then
    return M.flatten(roots)
  end

  -- Emit `node` and its subtree, descending only into expanded branches — a scoped
  -- hit renders at the active fold level, not fully unfolded. Only the scoped root
  -- carries the match span.
  local function dump(node, depth, acc, span)
    local has_children = node.children ~= nil and #node.children > 0
    acc[#acc + 1] = {
      node = node,
      depth = depth,
      has_children = has_children,
      expanded = has_children and node.expanded,
      match_span = span,
    }
    if has_children and node.expanded then
      for _, child in ipairs(node.children) do
        dump(child, depth + 1, acc, nil)
      end
    end
  end

  -- Build the visible rows for `nodes`. A node is kept when it matches itself or
  -- has any kept descendant; kept branches are force-shown (expanded), matched
  -- rows carry the matcher's span, ancestor-only rows are flagged is_context.
  local function build(nodes, depth)
    local acc = {}
    for _, node in ipairs(nodes) do
      local m = matcher(node)
      if m and m.scope then
        dump(node, depth, acc, m.span) -- scoped hit: node + everything under it
      else
        local has_children = node.children ~= nil and #node.children > 0
        local child_rows = has_children and build(node.children, depth + 1) or {}
        if m or #child_rows > 0 then
          acc[#acc + 1] = {
            node = node,
            depth = depth,
            has_children = has_children,
            expanded = #child_rows > 0, -- open only when we actually reveal children
            match_span = m and m.span or nil,
            is_context = not m, -- ancestor-only rows (no self-match) render dimmed
          }
          for _, r in ipairs(child_rows) do
            acc[#acc + 1] = r
          end
        end
      end
    end
    return acc
  end
  return build(roots, 0)
end

-- Uniformly fold the tree to `level`: a branch at depth d (0-based) is expanded
-- iff d < level. So level 0 folds everything down to the roots, level 1 opens the
-- roots' direct children, and level >= M.max_level opens the whole tree. Mirrors
-- M.prepare's depth logic (without re-linking parents, already done on open) and is
-- what the shell's dynamic fold-level control drives.
function M.set_expanded_depth(roots, level)
  local function walk(nodes, depth)
    for _, node in ipairs(nodes) do
      if node.children and #node.children > 0 then
        node.expanded = depth < level
        walk(node.children, depth + 1)
      end
    end
  end
  walk(roots, 0)
end

-- The greatest fold level that still changes the tree: (max depth of any node that
-- has children) + 1, or 0 for a flat tree with nothing to fold. A full unfold is
-- level == M.max_level; it's the denominator of the fold-level indicator.
function M.max_level(roots)
  local maxd = -1
  local function walk(nodes, depth)
    for _, node in ipairs(nodes) do
      if node.children and #node.children > 0 then
        if depth > maxd then
          maxd = depth
        end
        walk(node.children, depth + 1)
      end
    end
  end
  walk(roots, 0)
  return maxd + 1
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
