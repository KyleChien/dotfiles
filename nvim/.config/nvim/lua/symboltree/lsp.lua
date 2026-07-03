-- symboltree.lsp — request document symbols and normalize both LSP response
-- shapes (DocumentSymbol[] nested, SymbolInformation[] flat) into one node tree.

local M = {}

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

-- Request symbols from every capable client and merge. Calls `callback(roots)`
-- with the merged node list, or `callback(nil)` if there are no symbols/clients.
function M.request(bufnr, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = METHOD })
  if vim.tbl_isempty(clients) then
    return callback(nil)
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
      callback(nil)
    else
      callback(merged)
    end
  end)
end

return M
