-- ABOUTME: Reads CLAUDE.md files and builds a session initialization prompt
-- ABOUTME: Forces Claude to process project rules as a user message at session start

local M = {}

local function file_exists(path)
  local expanded = vim.fn.expand(path)
  local f = io.open(expanded, 'r')
  if not f then return false end
  local content = f:read('*a')
  f:close()
  return content and #content > 0
end

function M.build_init_prompt(paths)
  if not paths then
    local config = require('claude.config')
    paths = config.get().claude_md_paths
  end

  local refs = {}
  for _, entry in ipairs(paths) do
    if file_exists(entry[1]) then
      table.insert(refs, '@' .. entry[1])
    end
  end

  if #refs == 0 then return nil end

  return 'IMPORTANT: You MUST read and follow ALL rules in the files referenced below. '
    .. 'Confirm you have read them, then wait for instructions.\n\n'
    .. table.concat(refs, '\n')
end

return M
