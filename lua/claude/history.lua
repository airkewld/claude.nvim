-- ABOUTME: Reads past Claude CLI sessions from ~/.claude/projects JSONL files
-- ABOUTME: Extracts session id, first prompt, cwd, and last activity for resuming

local M = {}

local function flatten(text)
  return (text:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function parse_lines(lines)
  for _, line in ipairs(lines) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok
      and type(entry) == 'table'
      and entry.type == 'user'
      and not entry.isMeta
      and type(entry.message) == 'table'
      and type(entry.message.content) == 'string'
    then
      return { title = flatten(entry.message.content), cwd = entry.cwd }
    end
  end
  return {}
end

M._parse_lines = parse_lines

local MAX_HEAD_LINES = 50

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

function M.list(root)
  root = root or vim.fn.expand('~/.claude/projects')
  local entries = {}
  for _, path in ipairs(vim.fn.glob(root .. '/*/*.jsonl', true, true)) do
    local stat = vim.uv.fs_stat(path)
    if stat then
      local head = parse_lines(read_head(path))
      table.insert(entries, {
        id = vim.fn.fnamemodify(path, ':t:r'),
        title = head.title or '(no prompt)',
        cwd = head.cwd,
        mtime = stat.mtime.sec,
      })
    end
  end
  table.sort(entries, function(a, b) return a.mtime > b.mtime end)
  return entries
end

function M.filter_by_cwd(entries, cwd)
  return vim.tbl_filter(function(e) return e.cwd == cwd end, entries)
end

return M
