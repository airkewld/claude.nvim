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

  -- Helper: strip the trailing --session-id <uuid> from captured args
  local function args_without_session_id(args)
    if not args then return nil end
    local n = #args
    if n >= 2 and args[n - 1] == '--session-id' then
      local result = {}
      for i = 1, n - 2 do
        table.insert(result, args[i])
      end
      return result
    end
    return args
  end

  it('prepends default cli_args when no user args given', function()
    config.setup({})
    session = require('claude.session')

    session.create('test-session')
    assert.same({ '--permission-mode', 'plan' }, args_without_session_id(captured_args))
  end)

  it('prepends cli_args before user args', function()
    config.setup({})
    session = require('claude.session')

    session.create('test-session', { '--resume' })
    assert.same({ '--permission-mode', 'plan', '--resume' }, args_without_session_id(captured_args))
  end)

  it('passes only user args when cli_args is empty', function()
    config.setup({ cli_args = {} })
    session = require('claude.session')

    session.create('test-session', { '--resume' })
    assert.same({ '--resume' }, args_without_session_id(captured_args))
  end)

  it('passes --session-id when both cli_args and user args are empty', function()
    config.setup({ cli_args = {} })
    session = require('claude.session')

    local s = session.create('test-session')
    assert.same({ '--session-id', s.session_id }, captured_args)
  end)

  it('always appends --session-id as the last args', function()
    config.setup({})
    session = require('claude.session')

    local s = session.create('test-session')
    local n = #captured_args
    assert.equals('--session-id', captured_args[n - 1])
    assert.equals(s.session_id, captured_args[n])
  end)
end)
