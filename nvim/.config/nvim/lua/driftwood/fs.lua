-- driftwood.fs — filesystem helpers for the files provider. Pure OS/IO plumbing
-- (scandir, gitignore filtering, trashing, applying a derived op list); no window
-- or tree knowledge. Kept separate so providers/files.lua stays about presentation.

local uv = vim.uv or vim.loop

local M = {}

-- The git worktree root containing `dir`, or nil if it isn't in a repo.
function M.git_root(dir)
  local out = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then
    return nil
  end
  return out[1]
end

-- The set of absolute paths git ignores under `dir`, computed in a single call so
-- a full recursive scan needn't shell out per directory. Ignored directories are
-- returned collapsed (their contents aren't enumerated), which is fine: the walk
-- drops the directory node and never descends into it. Empty when not a repo.
function M.ignored_set(dir)
  local out = vim.fn.systemlist({
    "git", "-C", dir, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory",
  })
  local set = {}
  if vim.v.shell_error ~= 0 then
    return set
  end
  for _, line in ipairs(out) do
    line = line:gsub("/+$", "") -- `--directory` gives ignored dirs a trailing slash
    if line ~= "" then
      set[dir .. "/" .. line] = true
    end
  end
  return set
end

-- List `dir`'s entries as { name, path, is_dir }, dirs first then case-insensitive
-- by name. `opts.show_hidden` keeps dotfiles; `opts.ignored` (a path set, e.g. from
-- M.ignored_set) drops gitignored paths. Returns {} on an unreadable dir.
function M.scandir(dir, opts)
  opts = opts or {}
  local fd = uv.fs_scandir(dir)
  if not fd then
    return {}
  end
  local entries = {}
  while true do
    local name, t = uv.fs_scandir_next(fd)
    if not name then
      break
    end
    local path = dir .. "/" .. name
    local hidden = name:sub(1, 1) == "."
    local ignored = opts.ignored and opts.ignored[path]
    if (opts.show_hidden or not hidden) and not ignored then
      local is_dir = t == "directory"
      if t == "link" then -- resolve symlinks so directories still expand
        local st = uv.fs_stat(path)
        is_dir = st ~= nil and st.type == "directory"
      end
      entries[#entries + 1] = { name = name, path = path, is_dir = is_dir }
    end
  end

  table.sort(entries, function(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

-- ── mutations ────────────────────────────────────────────────────────────────

-- Recursively ensure `dir` exists (mkdir -p). Returns true on success.
local function mkdirp(dir)
  if uv.fs_stat(dir) then
    return true
  end
  local parent = vim.fs.dirname(dir)
  if parent and parent ~= dir then
    mkdirp(parent)
  end
  return uv.fs_mkdir(dir, tonumber("755", 8)) ~= nil
end
M.mkdirp = mkdirp

-- Move `path` to the system trash (recoverable), never a hard rm. Order: an
-- explicit `trash_cmd`, then a `trash` binary on PATH, then macOS Finder via
-- osascript. Returns ok, err — a hard failure so callers never silently delete.
function M.trash(path, trash_cmd)
  if trash_cmd then
    vim.fn.system(vim.list_extend(vim.deepcopy(trash_cmd), { path }))
    return vim.v.shell_error == 0, "trash_cmd failed"
  end
  if vim.fn.executable("trash") == 1 then
    vim.fn.system({ "trash", path })
    return vim.v.shell_error == 0, "trash failed"
  end
  if vim.fn.has("mac") == 1 then
    local script = 'tell application "Finder" to delete POSIX file "' .. path .. '"'
    vim.fn.system({ "osascript", "-e", script })
    return vim.v.shell_error == 0, "osascript trash failed"
  end
  return false, "no trash mechanism available (install `trash`)"
end

local function copy_recursive(src, dst)
  local st = uv.fs_stat(src)
  if not st then
    return false, "source missing"
  end
  if st.type == "directory" then
    mkdirp(dst)
    local fd = uv.fs_scandir(src)
    while fd do
      local name = uv.fs_scandir_next(fd)
      if not name then
        break
      end
      copy_recursive(src .. "/" .. name, dst .. "/" .. name)
    end
    return true
  end
  mkdirp(vim.fs.dirname(dst))
  return uv.fs_copyfile(src, dst, nil)
end

-- Execute one op. See M.apply_ops for the op shapes.
local function apply_one(op, trash_cmd)
  if op.kind == "create" then
    if op.is_dir then
      return mkdirp(op.path)
    end
    mkdirp(vim.fs.dirname(op.path))
    local fd = uv.fs_open(op.path, "a", tonumber("644", 8))
    if not fd then
      return false, "could not create"
    end
    uv.fs_close(fd)
    return true
  elseif op.kind == "move" then
    mkdirp(vim.fs.dirname(op.dest))
    local ok = uv.fs_rename(op.src, op.dest)
    if ok then
      return true
    end
    -- Cross-device (EXDEV) or similar: fall back to copy + trash the original.
    local cok, cerr = copy_recursive(op.src, op.dest)
    if not cok then
      return false, cerr
    end
    return M.trash(op.src, trash_cmd)
  elseif op.kind == "copy" then
    return copy_recursive(op.src, op.dest)
  elseif op.kind == "delete" then
    return M.trash(op.path, trash_cmd)
  end
  return false, "unknown op: " .. tostring(op.kind)
end

-- Apply a derived op list (from the files provider's parse_edit). Op shapes:
--   { kind = "create", path, is_dir }
--   { kind = "move",   src, dest, is_dir }
--   { kind = "copy",   src, dest }
--   { kind = "delete", path, is_dir }
-- Creates/moves/copies run first, deletes last, so emptying then removing a dir
-- (or moving a child out before its parent is trashed) stays safe. Calls
-- cb(errors) with a list of human-readable failure strings (empty on full success).
function M.apply_ops(ops, cb, trash_cmd)
  local ordered = {}
  for _, op in ipairs(ops) do
    if op.kind ~= "delete" then
      ordered[#ordered + 1] = op
    end
  end
  for _, op in ipairs(ops) do
    if op.kind == "delete" then
      ordered[#ordered + 1] = op
    end
  end

  local errors = {}
  for _, op in ipairs(ordered) do
    local ok, err = apply_one(op, trash_cmd)
    if not ok then
      errors[#errors + 1] = op.kind .. ": " .. (err or "failed")
    end
  end
  cb(errors)
end

return M
