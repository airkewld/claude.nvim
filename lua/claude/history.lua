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
      elseif content:match('^%s*<local%-command') then
        -- local command output, not a human prompt; keep scanning
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

local MAX_PREVIEW_LINES = 500

local function tool_hint(input)
  if type(input) ~= 'table' then return '' end
  for _, key in ipairs({ 'file_path', 'command', 'description', 'pattern', 'path' }) do
    local value = input[key]
    if type(value) == 'string' and value ~= '' then
      return ' ' .. flatten(value):sub(1, 60)
    end
  end
  return ''
end

local function append_block(out, label, text)
  local body = vim.split(text, '\n', { plain = true })
  out[#out + 1] = label .. (body[1] or '')
  for i = 2, #body do
    out[#out + 1] = body[i]
  end
  out[#out + 1] = ''
end

local function render_transcript(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if #out >= MAX_PREVIEW_LINES then
      out[#out + 1] = '… (truncated)'
      break
    end
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == 'table' and type(entry.message) == 'table' then
      local content = entry.message.content
      if entry.type == 'user'
        and type(content) == 'string'
        and not entry.isMeta
        and not content:match('^%s*<command%-name>')
        and not content:match('^%s*<local%-command')
      then
        append_block(out, 'You: ', content)
      elseif entry.type == 'assistant' and type(content) == 'table' then
        for _, block in ipairs(content) do
          if block.type == 'text' and type(block.text) == 'string' then
            append_block(out, 'Claude: ', block.text)
          elseif block.type == 'tool_use' then
            out[#out + 1] = '  [tool: ' .. (block.name or '?') .. tool_hint(block.input) .. ']'
          end
        end
        out[#out + 1] = ''
      end
    end
  end
  return out
end

M._render_transcript = render_transcript

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

function M.transcript(path)
  local fh = io.open(path, 'r')
  if not fh then return {} end
  local lines = {}
  for line in fh:lines() do
    table.insert(lines, line)
  end
  fh:close()
  return render_transcript(lines)
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
