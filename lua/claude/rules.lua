-- ABOUTME: Reads CLAUDE.md files and builds a session initialization prompt
-- ABOUTME: Forces Claude to process project rules as a user message at session start

local M = {}

local function read_file(path)
  local expanded = vim.fn.expand(path)
  local f = io.open(expanded, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  if content and #content > 0 then
    return content
  end
  return nil
end

function M.build_init_prompt(paths)
  if not paths then
    local config = require('claude.config')
    paths = config.get().claude_md_paths
  end

  local sections = {}
  for _, entry in ipairs(paths) do
    local content = read_file(entry[1])
    if content then
      table.insert(sections, string.format('=== %s ===\n%s', entry[2], content))
    end
  end

  if #sections == 0 then return nil end

  return 'IMPORTANT: Read and strictly follow these rules throughout this session:\n\n'
    .. table.concat(sections, '\n\n')
    .. '\n\nBriefly acknowledge these rules, then wait for my instructions.'
end

return M
