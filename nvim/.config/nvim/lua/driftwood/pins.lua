-- driftwood.pins — the on-disk pin store (generic, symbol-agnostic).
--
-- A pin is an opaque string key (built by the active provider's pin_key) scoped
-- to an absolute file path. The whole store is one JSON file under stdpath("data"):
--   { [abs_path] = { key, key, … } }   -- order = document order at last write
-- It's loaded once into `cache` and written through on every mutation (the file is
-- tiny, so this is durable against a crash with no save-on-exit).

local M = {}

local path = vim.fn.stdpath("data") .. "/driftwood/pins.json"

-- Lazily-loaded map file -> { key, … }. nil until first access.
local cache = nil

local function load()
  if cache then
    return cache
  end
  cache = {}
  if vim.fn.filereadable(path) == 1 then
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if ok and type(data) == "table" then
      cache = data
    end
  end
  return cache
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.json.encode, cache or {})
  if ok then
    pcall(vim.fn.writefile, { encoded }, path)
  end
end

-- The pin keys for `file` (a list, possibly empty). Never returns nil.
function M.get(file)
  return load()[file] or {}
end

-- Replace the pin keys for `file` and persist. An empty list drops the file entry
-- so the store doesn't accumulate empty buckets.
function M.set_keys(file, keys)
  load()
  cache[file] = (keys and #keys > 0) and keys or nil
  save()
end

-- Toggle `key` for `file` (append if absent, remove if present) and persist.
-- Appending keeps document order roughly right; the shell renumbers on render.
function M.toggle(file, key)
  local keys = vim.deepcopy(M.get(file))
  for i, k in ipairs(keys) do
    if k == key then
      table.remove(keys, i)
      M.set_keys(file, keys)
      return
    end
  end
  keys[#keys + 1] = key
  M.set_keys(file, keys)
end

return M
