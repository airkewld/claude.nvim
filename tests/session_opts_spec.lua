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
