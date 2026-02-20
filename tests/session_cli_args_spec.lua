-- ABOUTME: Tests that session.create() prepends config cli_args to user args
-- ABOUTME: Uses a stub for terminal.create to capture the args passed through

describe('session.create cli_args', function()
  local session
  local config
  local captured_args

  before_each(function()
    captured_args = nil

    -- Reset modules
    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.terminal'] = nil

    -- Stub terminal.create to capture args and return fake buf/job
    package.loaded['claude.terminal'] = {
      create = function(args)
        captured_args = args
        local bufnr = vim.api.nvim_create_buf(false, true)
        return bufnr, -1
      end,
    }

    config = require('claude.config')
    -- Stub vim.fn.executable so session.create doesn't bail
    vim.fn.executable = function() return 1 end
  end)

  it('prepends default cli_args when no user args given', function()
    config.setup({})
    session = require('claude.session')

    session.create('test-session')
    assert.same({ '--permission-mode', 'plan' }, captured_args)
  end)

  it('prepends cli_args before user args', function()
    config.setup({})
    session = require('claude.session')

    session.create('test-session', { '--resume' })
    assert.same({ '--permission-mode', 'plan', '--resume' }, captured_args)
  end)

  it('passes only user args when cli_args is empty', function()
    config.setup({ cli_args = {} })
    session = require('claude.session')

    session.create('test-session', { '--resume' })
    assert.same({ '--resume' }, captured_args)
  end)

  it('passes nil when both cli_args and user args are empty', function()
    config.setup({ cli_args = {} })
    session = require('claude.session')

    session.create('test-session')
    assert.is_nil(captured_args)
  end)
end)
