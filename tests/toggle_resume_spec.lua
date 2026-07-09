-- ABOUTME: Tests that toggling with no session offers to resume past sessions
-- ABOUTME: Drives the bare :Claude command with stubbed history and resume modules

describe('toggle resume offer', function()
  local history_entries
  local resume_opened_with
  local created
  local active_session

  before_each(function()
    history_entries = {}
    resume_opened_with = nil
    created = nil
    active_session = nil

    for _, mod in ipairs({
      'claude', 'claude.config', 'claude.session', 'claude.menu',
      'claude.window', 'claude.history', 'claude.resume', 'claude.terminal',
    }) do
      package.loaded[mod] = nil
    end

    package.loaded['claude.history'] = {
      list = function() return history_entries end,
    }
    package.loaded['claude.resume'] = {
      open = function(entries) resume_opened_with = entries end,
    }
    package.loaded['claude.session'] = {
      get_active = function() return active_session end,
      get_winnr = function() return nil end,
      set_winnr = function() end,
      create = function()
        created = true
        active_session = { name = 'fresh', bufnr = vim.api.nvim_create_buf(false, true), is_alive = true }
        return active_session
      end,
      find_by_bufnr = function() return nil, nil end,
      mark_input = function() end,
      is_idle = function() return false end,
      on_exit = function() end,
    }

    require('claude').setup({})
  end)

  it('opens the resume picker when history exists and no session is active', function()
    history_entries = { { id = 'abc', title = 't', cwd = '/p', mtime = os.time() } }
    vim.cmd('Claude')
    assert.same(history_entries, resume_opened_with)
    assert.is_nil(created)
  end)

  it('creates a new session when there is no history', function()
    vim.cmd('Claude')
    assert.is_true(created)
    assert.is_nil(resume_opened_with)
  end)

  it('does not consult history when a session is already active', function()
    active_session = { name = 'live', bufnr = vim.api.nvim_create_buf(false, true), is_alive = true }
    history_entries = { { id = 'abc', title = 't', cwd = '/p', mtime = os.time() } }
    vim.cmd('Claude')
    assert.is_nil(resume_opened_with)
    assert.is_nil(created)
  end)
end)
