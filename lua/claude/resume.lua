-- ABOUTME: Opens Claude's native `--resume` picker to resume a past CLI session
-- ABOUTME: Spawns a session terminal in the current project; Claude handles selection

local M = {}

function M.open()
  local session = require('claude.session')
  local s = session.create(nil, { '--resume' }, { cwd = vim.fn.getcwd() })
  if s then require('claude').switch_to_active() end
end

return M
