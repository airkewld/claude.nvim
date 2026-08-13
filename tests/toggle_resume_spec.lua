-- ABOUTME: Tests that toggling with no active session starts a fresh one
-- ABOUTME: Drives the bare :Claude command with a stubbed session module

describe('toggle with no active session', function()
  local created
  local active_session

  before_each(function()
    created = nil
    active_session = nil

    for _, mod in ipairs({
      'claude', 'claude.config', 'claude.session', 'claude.menu',
      'claude.window', 'claude.resume', 'claude.terminal',
    }) do
      package.loaded[mod] = nil
    end

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

  it('creates a new session when none is active', function()
    vim.cmd('Claude')
    assert.is_true(created)
  end)

  it('does not create a new session when one is already active', function()
    active_session = { name = 'live', bufnr = vim.api.nvim_create_buf(false, true), is_alive = true }
    vim.cmd('Claude')
    assert.is_nil(created)
  end)
end)
