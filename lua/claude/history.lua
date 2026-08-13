-- ABOUTME: Reads past Claude CLI sessions from ~/.claude/projects JSONL files
-- ABOUTME: Extracts session id, first prompt, cwd, and last activity for resuming

local M = {}

local function flatten(text)
  return (text:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function parse_lines(lines)
  local cwd
  local command_only = false
  for _, line in ipairs(lines) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok
      and type(entry) == 'table'
      and entry.type == 'user'
      and not entry.isMeta
      and type(entry.message) == 'table'
      and type(entry.message.content) == 'string'
    then
      if not cwd then cwd = entry.cwd end
      local content = entry.message.content
      if content:match('^%s*<command%-name>') then
        command_only = true
      else
        return { title = flatten(content), cwd = entry.cwd }
      end
    end
  end
  return { cwd = cwd, command_only = command_only }
end

M._parse_lines = parse_lines

local function parse_name(lines)
  local name
  for _, line in ipairs(lines) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok
      and type(entry) == 'table'
      and entry.type == 'agent-name'
      and type(entry.agentName) == 'string'
    then
      name = entry.agentName
    end
  end
  return name
end

M._parse_name = parse_name

local MAX_HEAD_LINES = 50
local TAIL_BYTES = 64 * 1024

local function read_head(path)
  local fh = io.open(path, 'r')
  if not fh then return {} end
  local lines = {}
  for line in fh:lines() do
    table.insert(lines, line)
    if #lines >= MAX_HEAD_LINES then break end
  end
  fh:close()
  return lines
end

local function read_tail(path, size)
  local fh = io.open(path, 'r')
  if not fh then return {} end
  local offset = math.max(size - TAIL_BYTES, 0)
  fh:seek('set', offset)
  local chunk = fh:read('*a') or ''
  fh:close()
  local lines = vim.split(chunk, '\n', { plain = true })
  if offset > 0 then
    -- first line is likely cut mid-entry; parse_name skips it as unparseable
    table.remove(lines, 1)
  end
  return lines
end

function M.list(root)
  root = root or vim.fn.expand('~/.claude/projects')
  local entries = {}
  for _, path in ipairs(vim.fn.glob(root .. '/*/*.jsonl', true, true)) do
    local stat = vim.uv.fs_stat(path)
    if stat then
      local head = parse_lines(read_head(path))
      if not head.command_only then
        table.insert(entries, {
          id = vim.fn.fnamemodify(path, ':t:r'),
          path = path,
          title = head.title or '(no prompt)',
          name = parse_name(read_tail(path, stat.size)),
          cwd = head.cwd,
          mtime = stat.mtime.sec,
        })
      end
    end
  end
  table.sort(entries, function(a, b) return a.mtime > b.mtime end)
  return entries
end

function M.filter_by_cwd(entries, cwd)
  return vim.tbl_filter(function(e) return e.cwd == cwd end, entries)
end

function M.delete(entry)
  if not entry or not entry.path then return false end
  if vim.fn.filereadable(entry.path) ~= 1 then return false end
  vim.fn.delete(entry.path)
  local checkpoint_dir = entry.path:gsub('%.jsonl$', '')
  if vim.fn.isdirectory(checkpoint_dir) == 1 then
    vim.fn.delete(checkpoint_dir, 'rf')
  end
  return true
end

return M
