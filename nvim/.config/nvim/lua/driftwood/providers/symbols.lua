-- driftwood.providers.symbols — the LSP document-symbol provider. Owns
-- everything symbol-specific: fetching + normalizing document symbols, turning a
-- node into a line + highlight spans, and the jump-to-symbol action. The generic
-- shell (window / render loop / tree) knows none of this.
--
-- Provider contract (informal — see docs/driftwood-design.md, approach A):
--   fetch(bufnr, cb)   → cb(roots) with a node tree, or cb(nil) if empty.
--   render(row, cfg)   → text, spans  where spans = { {s_col, e_col, group}, … }.
--   actions[name](ctx) → provider-specific action; ctx = { node, origin_win, close }.

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

-- ── render: node -> line text + highlight spans ──────────────────────────────

-- Returns the line text plus a list of { start_col, end_col, hl_group } byte
-- spans (0-based, within the line). `layout` is the active layout name; content
-- varies by layout via cfg.content[layout] (e.g. wider layouts show line numbers).
function M.render(row, cfg, layout)
  local node = row.node
  local indent = string.rep("  ", row.depth)
  local chevron
  if row.has_children then
    chevron = node.expanded and cfg.chevron.expanded or cfg.chevron.collapsed
  else
    chevron = " "
  end
  local icon = cfg.icons[node.kind] or cfg.icons.default
  local prefix = indent .. chevron .. " "
  local icon_part = icon .. " "
  local text = prefix .. icon_part .. node.name

  local group = cfg.kind_hl[node.kind] or cfg.hl.name
  local spans = {}
  if row.has_children then
    spans[#spans + 1] = { #indent, #indent + #chevron, cfg.hl.chevron }
  end
  spans[#spans + 1] = { #prefix, #prefix + #icon, group }
  spans[#spans + 1] = { #prefix + #icon_part, #text, group } -- name span (name-only length)

  -- Per-layout extra content: append the symbol's line number when enabled.
  local lc = cfg.content and cfg.content[layout]
  if lc and lc.show_lnum then
    local name_end = #text
    text = text .. "  " .. tostring(node.selection_range.start.line + 1)
    spans[#spans + 1] = { name_end, #text, cfg.hl.lnum or "Comment" }
  end

  return text, spans
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
