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

return M
