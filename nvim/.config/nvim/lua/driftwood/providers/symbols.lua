-- driftwood.providers.symbols — the LSP document-symbol provider. Owns
-- everything symbol-specific: fetching + normalizing document symbols, turning a
-- node into a line + highlight spans, and the jump-to-symbol action. The generic
-- shell (window / render loop / tree) knows none of this.
--
-- Provider contract (informal — see docs/driftwood-design.md, approach A):
--   fetch(bufnr, cb)     → cb(roots) with a node tree, or cb(nil) if empty.
--   render(row, cfg)     → text, spans  where spans = { {s_col, e_col, group}, … }.
--   actions[name](ctx)   → provider-specific action; ctx = { node, origin_win, close }.
--   make_matcher(query)  → fn(node) -> false | { span }; the live-filter predicate
--                          (see the filter section below). Symbol-specific because
--                          only the provider knows what a SymbolKind is named.

local M = {}

-- Stable provider name, used by the shell to key per-provider session state
-- (e.g. the sticky layout). Must match the `providers.<name>` config key.
M.name = "symbols"

-- ── fetch: request document symbols + normalize both LSP shapes ──────────────

local METHOD = "textDocument/documentSymbol"

-- DocumentSymbol: nested, has `range` + `selectionRange` (+ optional `children`).
local function from_document_symbol(item)
  local node = {
    name = (item.name or "?"):gsub("[\r\n]", " "),
    kind = item.kind,
    range = item.range,
    selection_range = item.selectionRange or item.range,
    children = {},
  }
  if item.children then
    for _, child in ipairs(item.children) do
      node.children[#node.children + 1] = from_document_symbol(child)
    end
  end
  return node
end

-- SymbolInformation: flat, only a `location`. No hierarchy.
local function from_symbol_information(item)
  return {
    name = (item.name or "?"):gsub("[\r\n]", " "),
    kind = item.kind,
    range = item.location.range,
    selection_range = item.location.range,
    children = {},
  }
end

local function normalize(result)
  local nodes = {}
  for _, item in ipairs(result) do
    if item.location ~= nil then
      nodes[#nodes + 1] = from_symbol_information(item)
    else
      nodes[#nodes + 1] = from_document_symbol(item)
    end
  end
  return nodes
end

-- Request symbols from every capable client and merge. Calls `cb(roots)` with
-- the merged node list, or `cb(nil)` if there are no symbols/clients.
function M.fetch(bufnr, cb)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = METHOD })
  if vim.tbl_isempty(clients) then
    return cb(nil)
  end

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  vim.lsp.buf_request_all(bufnr, METHOD, params, function(results)
    local merged = {}
    for _, res in pairs(results) do
      if res.result then
        vim.list_extend(merged, normalize(res.result))
      end
    end
    if vim.tbl_isempty(merged) then
      cb(nil)
    else
      cb(merged)
    end
  end)
end

-- ── filter matcher: query -> per-node predicate ─────────────────────────────
-- The live filter (driftwood.ui / tree.flatten_filtered) is provider-agnostic: it
-- asks the provider for a matcher and force-shows every matched node plus its
-- ancestor path. A matcher maps a node to `false` (no match) or `{ span }`, where
-- `span` is a 0-based byte range within the name to highlight (nil for a match with
-- nothing to underline, e.g. a kind-only filter). Decoupling match-ness from `span`
-- is what lets a kind match be a real result without a highlighted substring.

-- Canonical SymbolKind (LSP numeric) -> display name, used only for kind filtering.
local KIND_NAMES = {
  [1] = "File",
  [2] = "Module",
  [3] = "Namespace",
  [4] = "Package",
  [5] = "Class",
  [6] = "Method",
  [7] = "Property",
  [8] = "Field",
  [9] = "Constructor",
  [10] = "Enum",
  [11] = "Interface",
  [12] = "Function",
  [13] = "Variable",
  [14] = "Constant",
  [15] = "String",
  [16] = "Number",
  [17] = "Boolean",
  [18] = "Array",
  [19] = "Object",
  [20] = "Key",
  [21] = "Null",
  [22] = "EnumMember",
  [23] = "Struct",
  [24] = "Event",
  [25] = "Operator",
  [26] = "TypeParameter",
}

-- Leading glyph that switches the query from a name search to a kind filter.
-- Exposed on M so the shell can bind it as a normal-mode key that opens the prompt
-- pre-seeded with the sigil (press `@` → straight into kind mode), keeping the key
-- and the parsed syntax in lockstep from a single source of truth.
local KIND_SIGIL = "@"
M.kind_sigil = KIND_SIGIL

-- Smartcase plain-substring search: returns a function name -> (s, e) 0-based byte
-- span or nil. Case-insensitive unless `query` contains an uppercase letter.
local function substring_search(query)
  local ignorecase = query == query:lower()
  local needle = ignorecase and query:lower() or query
  return function(name)
    local hay = ignorecase and name:lower() or name
    local s = hay:find(needle, 1, true)
    if s then
      return s - 1, s - 1 + #needle
    end
    return nil
  end
end

-- Build the live-filter predicate for `query`.
--   A query is split into an optional `@kind` token and a name substring, in any
--   order — `@function proc`, `proc @function`, and `pr@func oc`ing all parse the
--   same. The `@…` token (matched anywhere) is a case-insensitive PREFIX over
--   KIND_NAMES, unioned across every kind it prefixes (bare `@` → all kinds); the
--   leftover text (everything that isn't the `@` token) is ANDed as a name
--   substring (smartcase). A kind-only match carries no span (nothing to underline).
--   With no `@`, the whole query is a plain name substring — the original behavior.
function M.make_matcher(query)
  -- Extract the first `@kind` token from anywhere in the query; the remainder
  -- (with the token spliced out) is the name part. Order-independent by design.
  if query:find(KIND_SIGIL, 1, true) then
    local kind_token
    local name_part = query:gsub(KIND_SIGIL .. "(%S*)", function(tok)
      kind_token = kind_token or tok
      return ""
    end)
    kind_token = (kind_token or ""):lower()
    name_part = vim.trim(name_part)

    -- Every SymbolKind whose name has `kind_token` as a prefix (empty → all).
    local kinds = {}
    for num, kname in pairs(KIND_NAMES) do
      if kname:lower():sub(1, #kind_token) == kind_token then
        kinds[num] = true
      end
    end

    local name_search = name_part ~= "" and substring_search(name_part) or nil
    return function(node)
      if not kinds[node.kind] then
        return false
      end
      if not name_search then
        return { span = nil } -- kind-only: a real match, no substring to highlight
      end
      local s, e = name_search(node.name)
      if not s then
        return false
      end
      return { span = { s, e } }
    end
  end

  local name_search = substring_search(query)
  return function(node)
    local s, e = name_search(node.name)
    if not s then
      return false
    end
    return { span = { s, e } }
  end
end

-- ── render: node -> line text + highlight spans ──────────────────────────────

-- Returns the line text plus a list of { start_col, end_col, hl_group } byte
-- spans (0-based, within the line). `layout` is the active layout name; content
-- varies by layout via cfg.content[layout] (e.g. wider layouts show line numbers).
function M.render(row, cfg, layout)
  local node = row.node
  local indent = string.rep("  ", row.depth)
  -- Prefer the row's fold flag (set by both flatten variants); under a filter it
  -- can differ from node.expanded, which filtering never touches.
  local open = row.expanded
  if open == nil then
    open = node.expanded
  end
  local chevron
  if row.has_children then
    chevron = open and cfg.chevron.expanded or cfg.chevron.collapsed
  else
    chevron = " "
  end
  local icon = cfg.icons[node.kind] or cfg.icons.default
  local prefix = indent .. chevron .. " "
  local icon_part = icon .. " "
  local text = prefix .. icon_part .. node.name

  -- Ancestor-only context rows (shown only because a descendant matched) render
  -- dimmed so real matches stand out.
  local search_hl = cfg.search and cfg.search.hl or {}
  local group = cfg.kind_hl[node.kind] or cfg.hl.name
  if row.is_context and search_hl.context then
    group = search_hl.context
  end
  local spans = {}
  if row.has_children then
    spans[#spans + 1] = { #indent, #indent + #chevron, cfg.hl.chevron }
  end
  local name_start = #prefix + #icon_part
  spans[#spans + 1] = { #prefix, #prefix + #icon, group }
  spans[#spans + 1] = { name_start, #text, group } -- name span (name-only length)

  -- Highlight the matched substring inside the name (added last so it draws over
  -- the name span). match_span is a 0-based byte range within the name.
  if row.match_span and search_hl.match then
    spans[#spans + 1] =
      { name_start + row.match_span[1], name_start + row.match_span[2], search_hl.match }
  end

  -- Per-layout extra content: append the symbol's line number when enabled.
  local lc = cfg.content and cfg.content[layout]
  if lc and lc.show_lnum then
    local name_end = #text
    text = text .. "  " .. tostring(node.selection_range.start.line + 1)
    spans[#spans + 1] = { name_end, #text, cfg.hl.lnum or "Comment" }
  end

  return text, spans
end

-- ── pins: stable identity for the shell's pin store ──────────────────────────
-- A pin is a string key (not a node — nodes are re-fetched every open). The shell
-- owns the on-disk store, badges, keys and numbering; the provider only says what
-- makes a symbol stably identifiable. Here that's the `kind:name` path from the
-- root down to the node, which survives the symbol moving lines and disambiguates
-- same-named symbols by their container path. Requires `node.parent` (set by
-- tree.prepare on open).

function M.pin_key(node)
  local parts = {}
  local n = node
  while n do
    parts[#parts + 1] = (n.kind or "?") .. ":" .. (n.name or "?")
    n = n.parent
  end
  -- parts is leaf→root; reverse to root→leaf so the key reads top-down.
  local rev = {}
  for i = #parts, 1, -1 do
    rev[#rev + 1] = parts[i]
  end
  return table.concat(rev, "/")
end

-- Re-locate a stored key against a freshly-fetched tree, or nil if it's gone
-- (symbol renamed/deleted → the shell prunes it). First match in pre-order.
function M.pin_match(roots, key)
  local found
  local function walk(nodes)
    for _, node in ipairs(nodes) do
      if found then
        return
      end
      if M.pin_key(node) == key then
        found = node
        return
      end
      if node.children then
        walk(node.children)
      end
    end
  end
  walk(roots)
  return found
end

-- ── actions ──────────────────────────────────────────────────────────────────

M.actions = {}

-- Jump to the symbol under the cursor: close the float, then place the origin
-- window's cursor on the symbol's selection range and recenter.
function M.actions.jump(ctx)
  local target = ctx.node.selection_range.start
  local win = ctx.origin_win
  ctx.close(false)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { target.line + 1, target.character })
    vim.cmd("normal! zz")
  end
end

return M
