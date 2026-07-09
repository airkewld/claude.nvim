-- ABOUTME: Tests that session.create() forwards opts.cwd to terminal.create
-- ABOUTME: and records the working directory on the session object

describe('session.create opts', function()
  local session
  local config
  local captured_opts

  before_each(function()
    captured_opts = nil

    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.terminal'] = nil

    package.loaded['claude.terminal'] = {
      create = function(_, opts)
        captured_opts = opts
        local bufnr = vim.api.nvim_create_buf(false, true)
        return bufnr, -1
      end,
    }

    config = require('claude.config')
    vim.fn.executable = function() return 1 end
  end)

  it('forwards opts.cwd to terminal.create', function()
    config.setup({})
    session = require('claude.session')

    session.create('with-cwd', nil, { cwd = '/some/dir' })
    assert.equals('/some/dir', captured_opts.cwd)
  end)

  it('sets cwd on the session object', function()
    config.setup({})
    session = require('claude.session')

    local s = session.create('with-cwd', nil, { cwd = '/some/dir' })
    assert.equals('/some/dir', s.cwd)
  end)

  it('defaults session cwd to the current directory', function()
    config.setup({})
    session = require('claude.session')

    local s = session.create('no-cwd')
    assert.equals(vim.fn.getcwd(), s.cwd)
    assert.is_true(captured_opts == nil or captured_opts.cwd == nil)
  end)
end)

describe('session.rename forwarding', function()
  local session
  local sent

  before_each(function()
    sent = nil

    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.terminal'] = nil

    package.loaded['claude.terminal'] = {
      create = function()
        return vim.api.nvim_create_buf(false, true), 42
      end,
      send_input = function(job_id, text)
        sent = { job_id = job_id, text = text }
      end,
    }

    require('claude.config').setup({})
    vim.fn.executable = function() return 1 end
    session = require('claude.session')
  end)

  it('sends /rename to a live session so the CLI persists it', function()
    session.create('old-name')
    assert.is_true(session.rename(1, 'new-name'))
    assert.equals(42, sent.job_id)
    assert.equals('/rename new-name', sent.text)
  end)

  it('does not send to a dead session', function()
    local s = session.create('old-name')
    s.is_alive = false
    assert.is_true(session.rename(1, 'new-name'))
    assert.is_nil(sent)
  end)
end)
