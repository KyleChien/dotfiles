-- driftwood.providers.files — an nvim-tree-like file tree with oil-style editing.
-- Owns everything file-specific: scanning the directory tree, rendering a node
-- into a line, opening a file, path-based pins, and the edit-mode diff (serialize
-- the tree → parse the edited buffer → file ops). The generic shell (window /
-- render loop / tree / pins) knows none of this.
--
-- The whole tree is scanned up front (so name search, @scope, and fold-level work
-- over every node), but *asynchronously*: fetch walks the tree on a coroutine that
-- yields to the event loop periodically, so the float opens immediately and shows
-- the shell's loading spinner — just like the LSP symbols provider — instead of
-- blocking on a large tree.
--
-- Provider contract (see docs/driftwood-design.md + providers/symbols.lua):
--   fetch(bufnr, cb, cfg)        → cb(roots): the full directory tree (async).
--   render(row, cfg, layout)     → text, spans.
--   make_matcher(query)          → per-node predicate; `@dir` sets scope = true.
--   pin_key/pin_match            → a file's absolute path is its stable identity.
--   pin_scope(cfg)               → pins are keyed per tree root, not per origin file.
--   actions.jump(ctx)            → open the file in the origin window.
--   editable + edit_serialize/parse_edit/preview_ops/apply_ops → oil-style editing.
--   toggle_hidden()              → flip dotfile/gitignore visibility, then reload.

local fs = require("driftwood.fs")

local M = {}

M.name = "files"

-- Runtime tree root + git worktree root for the current open (module-local: the
-- shell hosts a single float at a time). `show_hidden` is sticky runtime state
-- toggled by the `.` key; nil until the first fetch seeds it from config.
local root = nil
local git_root = nil
local show_hidden = nil

local function resolve_root(cfg)
  local r = cfg and cfg.root
  if r == nil or r == "" then
    r = vim.fn.getcwd()
  end
  return vim.fs.normalize(r)
end

-- Build the per-scan options. `ignored` (the gitignore path set) is filled in by
-- fetch, which computes it once for the whole tree.
local function scan_opts(cfg)
  local fo = (cfg and cfg.files_opts) or {}
  if show_hidden == nil then
    show_hidden = fo.show_hidden or false
  end
  return {
    show_hidden = show_hidden,
    gitignore = fo.gitignore ~= false,
  }
end

local function make_node(entry, parent)
  local node = {
    name = entry.name,
    path = entry.path,
    is_dir = entry.is_dir,
    kind = entry.is_dir and "dir" or "file",
    parent = parent,
  }
  if entry.is_dir then
    node.children = {} -- filled by the recursive walk (or left empty for an empty dir)
  end
  return node
end

-- ── fetch (full tree, async) ──────────────────────────────────────────────────

-- Yield to the event loop every this-many scanned directories so the shell's
-- loading spinner keeps animating on large trees.
local YIELD_EVERY = 200

function M.fetch(bufnr, cb, cfg)
  root = resolve_root(cfg)
  git_root = fs.git_root(root)
  local opts = scan_opts(cfg)
  if opts.gitignore and git_root then
    opts.ignored = fs.ignored_set(root) -- one git call for the whole tree
  end

  -- Walk the tree on a coroutine, yielding periodically. Each resume does a slice
  -- of work, then vim.schedule re-enters on the next loop tick (letting the spinner
  -- timer fire) until the walk completes and we hand the roots back.
  local scanned = 0
  local co = coroutine.create(function()
    local function build(dir, parent)
      local nodes = {}
      for _, entry in ipairs(fs.scandir(dir, opts)) do
        local node = make_node(entry, parent)
        nodes[#nodes + 1] = node
        if entry.is_dir then
          scanned = scanned + 1
          if scanned % YIELD_EVERY == 0 then
            coroutine.yield()
          end
          node.children = build(entry.path, node)
        end
      end
      return nodes
    end
    return build(root, nil)
  end)

  local function step()
    local ok, res = coroutine.resume(co)
    if not ok then
      cb(nil)
      return
    end
    if coroutine.status(co) == "dead" then
      cb(res)
    else
      vim.schedule(step)
    end
  end
  step()
end

function M.toggle_hidden()
  if show_hidden == nil then
    show_hidden = false
  end
  show_hidden = not show_hidden
  return show_hidden
end

-- ── filter matcher ────────────────────────────────────────────────────────────
-- `/name` = smartcase substring over the node name (loaded nodes only — lazy
-- loading means unexpanded dirs aren't searched until opened). `@dir` scopes the
-- tree to directories matching the token, showing each matched dir + its subtree.

local KIND_SIGIL = "@"
M.kind_sigil = KIND_SIGIL

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

function M.make_matcher(query)
  if query:sub(1, #KIND_SIGIL) == KIND_SIGIL then
    local token = query:sub(#KIND_SIGIL + 1)
    local search = token ~= "" and substring_search(token) or nil
    return function(node)
      if not node.is_dir then
        return false -- scope matches folders; files ride along as descendants
      end
      if not search then
        return { scope = true, span = nil } -- `@` alone scopes to every folder
      end
      local s, e = search(node.name)
      if not s then
        return false
      end
      return { scope = true, span = { s, e } }
    end
  end

  local search = substring_search(query)
  return function(node)
    local s, e = search(node.name)
    if not s then
      return false
    end
    return { span = { s, e } }
  end
end

-- ── icons ─────────────────────────────────────────────────────────────────────
-- Files get filetype-specific, colored glyphs from nvim-web-devicons when it's
-- available; directories use the configured folder glyphs. Everything degrades to
-- the plain cfg.icons glyphs when devicons isn't installed.

local devicons -- nil = unresolved, false = absent, else the module
local function get_devicons()
  if devicons == nil then
    local ok, mod = pcall(require, "nvim-web-devicons")
    devicons = ok and mod or false
  end
  return devicons or nil
end

-- The glyph + highlight group for `node`. Returns icon, hl_group.
local function icon_for(node, open, cfg)
  local icons = cfg.icons or {}
  local hl = cfg.hl or {}
  local dev = get_devicons()
  if node.is_dir then
    -- Recognized special directories (.git, node_modules, .github, …) get their
    -- devicons glyph; ordinary folders use the generic open/closed folder glyph.
    -- `default = false` so a plain folder falls through instead of matching a file.
    if dev then
      local glyph, ihl = dev.get_icon(node.name, nil, { default = false })
      if glyph then
        return glyph, ihl or hl.dir or "Directory"
      end
    end
    local glyph = (open and icons.dir_open) or icons.dir or icons.default or ""
    return glyph, hl.dir or "Directory"
  end
  if dev then
    local ext = node.name:match("%.([^.]+)$")
    local glyph, ihl = dev.get_icon(node.name, ext, { default = true })
    if glyph then
      return glyph, ihl or hl.name or "Normal"
    end
  end
  return icons.file or icons.default or "", hl.name or "Normal"
end

-- ── render ────────────────────────────────────────────────────────────────────

function M.render(row, cfg, layout)
  local node = row.node
  local indent = string.rep("  ", row.depth)
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

  local icon, icon_hl = icon_for(node, open, cfg)

  local prefix = indent .. chevron .. " "
  local icon_part = icon .. " "
  local name = node.name .. (node.is_dir and "/" or "")
  local text = prefix .. icon_part .. name

  local hl = cfg.hl or {}
  local group = node.is_dir and (hl.dir or "Directory") or (hl.name or "Normal")
  local search_hl = (cfg.search and cfg.search.hl) or {}
  if row.is_context and search_hl.context then
    group = search_hl.context
    icon_hl = search_hl.context -- dim ancestor-only rows' icons too
  end

  local spans = {}
  if row.has_children then
    spans[#spans + 1] = { #indent, #indent + #chevron, hl.chevron or "Comment" }
  end
  local name_start = #prefix + #icon_part
  spans[#spans + 1] = { #prefix, #prefix + #icon, icon_hl }
  spans[#spans + 1] = { name_start, #text, group }
  -- match_span is a 0-based byte range within the name (the trailing "/" is appended
  -- after, so it never falls inside the highlighted range).
  if row.match_span and search_hl.match then
    spans[#spans + 1] =
      { name_start + row.match_span[1], name_start + row.match_span[2], search_hl.match }
  end

  return text, spans
end

-- ── pins (absolute path identity, load-aware match) ───────────────────────────

function M.pin_key(node)
  return node.path
end

-- Pins are shared across the whole tree, not per origin file (which is what the
-- shell keys pins by for symbols). Return the tree root so a project's pins are
-- stable no matter which buffer was focused when the tree was opened.
function M.pin_scope(cfg)
  return resolve_root(cfg)
end

-- Fold level is cached per tree root (like pins), not per origin buffer: a
-- project's fold depth is shared no matter which file was focused when the tree
-- was opened. Symbols has no override, so its fold stays keyed per origin file.
function M.fold_scope(cfg)
  return resolve_root(cfg)
end

local function is_under(dir, path)
  return path:sub(1, #dir + 1) == dir .. "/"
end

-- Re-locate a path against the scanned tree. Returns nil ONLY when the path no
-- longer exists on disk (a real deletion → the caller prunes it). Otherwise it
-- walks from the root to the path; any node missing from the tree (e.g. a path now
-- hidden by the gitignore/dotfile filter) is synthesized and attached, so a valid
-- reference is never wrongly lost. Shared by pin_match (identity) and focus.
local function locate(roots, key, cfg)
  local r = root or resolve_root(cfg)
  if not vim.uv.fs_stat(key) then
    return nil
  end
  if key == r or not is_under(r, key) then
    return nil -- the root itself, or a path outside this tree
  end

  local rel = key:sub(#r + 2)
  local nodes, parent, cur = roots, nil, r
  local node = nil
  for seg in rel:gmatch("[^/]+") do
    cur = cur .. "/" .. seg
    local found = nil
    for _, n in ipairs(nodes) do
      if n.path == cur then
        found = n
        break
      end
    end
    if not found then
      local st = vim.uv.fs_stat(cur)
      if not st then
        return nil
      end
      found = make_node({ name = seg, path = cur, is_dir = st.type == "directory" }, parent)
      nodes[#nodes + 1] = found -- attach so force-show can surface it
    end
    node, parent, nodes = found, found, found.children or {}
  end
  return node
end

-- Only files carry pins. A dir hit resolves to nil so a stale directory pin from
-- before that rule auto-prunes on the next open (refresh_pins drops keys with no
-- match), and a folder can never be force-shown as a pin.
function M.pin_match(roots, key, cfg)
  local node = locate(roots, key, cfg)
  if node and node.is_dir then
    return nil
  end
  return node
end

-- Only files are pinnable; folders are structural. The shell consults this before
-- toggling a pin.
function M.can_pin(node)
  return not node.is_dir
end

-- The node for the origin buffer's file (or nil if it's outside this tree), so the
-- shell can focus + reveal the current file each time the tree opens.
function M.focus(roots, origin, cfg)
  local path = origin and origin.path
  if not path or path == "" then
    return nil
  end
  return locate(roots, path, cfg)
end

-- ── actions ───────────────────────────────────────────────────────────────────

M.actions = {}

-- Open the file in the origin window. Directories never reach here — the shell's
-- generic `activate` action toggles them instead.
function M.actions.jump(ctx)
  local node = ctx.node
  if node.is_dir then
    return
  end
  local win = ctx.origin_win
  ctx.close(false)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

-- ── oil-style editing ─────────────────────────────────────────────────────────
-- The shell flips the tree buffer editable, feeds each row through edit_serialize
-- to a clean `indent + name` line, tracks each line's source path via extmarks,
-- and on commit hands back the edited lines (with surviving orig paths) here to
-- diff into a file-op list.

M.editable = true

function M.edit_serialize(row)
  local node = row.node
  return string.rep("  ", row.depth) .. node.name .. (node.is_dir and "/" or "")
end

-- Diff the edited buffer into ops. `entries` = ordered { text, orig_id } (orig_id =
-- the path this line came from, or nil for a freshly typed line). `originals` =
-- { path, is_dir } present when editing began (for deletion detection). `tree_root`
-- = the absolute root the indentation is relative to.
--   indent (2 spaces/level) rebuilds the parent chain: a line's parent is the last
--   directory one level shallower. name change or a shallower/deeper indent under a
--   different parent ⇒ move; a new line ⇒ create; an orig path with no surviving
--   line ⇒ delete.
function M.parse_edit(entries, originals, tree_root)
  local ops = {}
  local seen = {}
  local parents = { [0] = tree_root } -- depth → parent dir path for that depth's kids

  for _, e in ipairs(entries) do
    local leading = e.text:match("^%s*")
    local depth = math.floor(#leading / 2)
    local name = vim.trim(e.text)
    local is_dir = name:sub(-1) == "/"
    name = name:gsub("/+$", "")
    if name ~= "" and name ~= "." and name ~= ".." then
      local parent = parents[depth] or tree_root
      local newpath = parent .. "/" .. name
      if is_dir then
        parents[depth + 1] = newpath
      end
      if e.orig_id then
        seen[e.orig_id] = true
        if e.orig_id ~= newpath then
          ops[#ops + 1] = { kind = "move", src = e.orig_id, dest = newpath, is_dir = is_dir }
        end
      else
        ops[#ops + 1] = { kind = "create", path = newpath, is_dir = is_dir }
      end
    end
  end

  for _, o in ipairs(originals) do
    if not seen[o.path] then
      ops[#ops + 1] = { kind = "delete", path = o.path, is_dir = o.is_dir }
    end
  end
  return ops
end

function M.preview_ops(ops)
  local function rel(p)
    return (root and is_under(root, p)) and p:sub(#root + 2) or p
  end
  local lines = {}
  for _, op in ipairs(ops) do
    if op.kind == "create" then
      lines[#lines + 1] = "NEW  " .. rel(op.path) .. (op.is_dir and "/" or "")
    elseif op.kind == "move" then
      lines[#lines + 1] = "MV   " .. rel(op.src) .. "  →  " .. rel(op.dest)
    elseif op.kind == "copy" then
      lines[#lines + 1] = "CP   " .. rel(op.src) .. "  →  " .. rel(op.dest)
    elseif op.kind == "delete" then
      lines[#lines + 1] = "RM   " .. rel(op.path) .. (op.is_dir and "/" or "")
    end
  end
  return lines
end

function M.apply_ops(ops, cb, cfg)
  local trash_cmd = ((cfg and cfg.files_opts) or {}).trash_cmd
  fs.apply_ops(ops, cb, trash_cmd)
end

return M
