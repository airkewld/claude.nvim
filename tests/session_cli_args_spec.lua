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
    package.loaded['claude.persistence'] = nil

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
    assert.same({ '--permission-mode', 'plan', '--name', vim.fn.shellescape('test-session') }, captured_args)
  end)

  it('prepends cli_args before user args', function()
    config.setup({})
    session = require('claude.session')

    session.create('test-session', { '--resume' })
    assert.same({ '--permission-mode', 'plan', '--resume', '--name', vim.fn.shellescape('test-session') }, captured_args)
  end)

  it('passes only user args when cli_args is empty', function()
    config.setup({ cli_args = {} })
    session = require('claude.session')

    session.create('test-session', { '--resume' })
    assert.same({ '--resume', '--name', vim.fn.shellescape('test-session') }, captured_args)
  end)

  it('passes only the name when both cli_args and user args are empty', function()
    config.setup({ cli_args = {} })
    session = require('claude.session')

    session.create('test-session')
    assert.same({ '--name', vim.fn.shellescape('test-session') }, captured_args)
  end)

  describe('--name injection', function()
    it('does not pass --name for auto-named sessions', function()
      config.setup({})
      session = require('claude.session')

      session.create()
      assert.is_false(vim.tbl_contains(captured_args, '--name'))
    end)

    it('skips injection when user args already contain --name', function()
      config.setup({ cli_args = {} })
      session = require('claude.session')

      session.create('test-session', { '--name', 'other' })
      assert.same({ '--name', 'other' }, captured_args)
    end)

    it('shell-escapes names with spaces', function()
      config.setup({ cli_args = {} })
      session = require('claude.session')

      session.create('my session')
      assert.same({ '--name', vim.fn.shellescape('my session') }, captured_args)
    end)
  end)

  it('does not pass --session-id', function()
    config.setup({})
    session = require('claude.session')

    session.create('test-session')
    assert.is_false(vim.tbl_contains(captured_args, '--session-id'))
  end)

  describe('CLAUDE_MODEL env var', function()
    local saved_env

    before_each(function()
      saved_env = vim.env.CLAUDE_MODEL
      vim.env.CLAUDE_MODEL = nil
    end)

    after_each(function()
      vim.env.CLAUDE_MODEL = saved_env
    end)

    it('does not inject --model when env var is unset', function()
      config.setup({})
      session = require('claude.session')

      session.create('test-session')
      assert.is_false(vim.tbl_contains(captured_args, '--model'))
    end)

    it('appends --model <value> when env var is set and no user --model', function()
      vim.env.CLAUDE_MODEL = 'haiku'
      config.setup({})
      session = require('claude.session')

      session.create('test-session')
      assert.same({ '--permission-mode', 'plan', '--model', 'haiku', '--name', vim.fn.shellescape('test-session') }, captured_args)
    end)

    it('skips env var when user passes --model', function()
      vim.env.CLAUDE_MODEL = 'haiku'
      config.setup({})
      session = require('claude.session')

      session.create('test-session', { '--model', 'sonnet' })
      assert.same({ '--permission-mode', 'plan', '--model', 'sonnet', '--name', vim.fn.shellescape('test-session') }, captured_args)
      -- only one --model entry, with the user's value
      local count = 0
      for _, a in ipairs(captured_args) do
        if a == '--model' then count = count + 1 end
      end
      assert.equals(1, count)
    end)

    it('treats empty env var as unset', function()
      vim.env.CLAUDE_MODEL = ''
      config.setup({})
      session = require('claude.session')

      session.create('test-session')
      assert.is_false(vim.tbl_contains(captured_args, '--model'))
    end)

    it('skips env var when config.cli_args already contains --model', function()
      vim.env.CLAUDE_MODEL = 'haiku'
      config.setup({ cli_args = { '--model', 'opus' } })
      session = require('claude.session')

      session.create('test-session')
      assert.same({ '--model', 'opus', '--name', vim.fn.shellescape('test-session') }, captured_args)
    end)
  end)
end)
