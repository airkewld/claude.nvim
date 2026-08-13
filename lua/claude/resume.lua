-- ABOUTME: Opens Claude's native `--resume` picker to resume a past CLI session
-- ABOUTME: Once the session settles, labels it with the resumed transcript's name

local M = {}

-- The native picker runs inside the terminal, so nvim never sees which session
-- was chosen. Once the resumed session settles, the most recently active
-- transcript for this project is the one that was picked; adopt its name.
function M._resolve_name(s)
  local history = require('claude.history')
  local newest = history.filter_by_cwd(history.list(), s.cwd)[1]
  if not newest then return end
  s.resume_id = newest.id
  if not newest.name then return end
  s.name = newest.name

  local session = require('claude.session')
  local winnr = session.get_winnr()
  if winnr and vim.api.nvim_win_is_valid(winnr) and session.get_active() == s then
    require('claude.window').set_title(winnr, newest.name)
  end
end

function M.open()
  local session = require('claude.session')
  local s = session.create(nil, { '--resume' }, { cwd = vim.fn.getcwd() })
  if not s then return end
  s.on_settled = function(sess) M._resolve_name(sess) end
  require('claude').switch_to_active()
end

return M
