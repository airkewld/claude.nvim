-- ABOUTME: Tests for session persistence integration
-- ABOUTME: Validates session_id assignment, dormant sessions, save/load/resume

describe('session persistence', function()
  local session
  local persistence
  local captured_args

  before_each(function()
    captured_args = nil

    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.terminal'] = nil
    package.loaded['claude.persistence'] = nil
    package.loaded['claude.rules'] = nil

    package.loaded['claude.terminal'] = {
      create = function(args)
        captured_args = args
        local bufnr = vim.api.nvim_create_buf(false, true)
        return bufnr, -1
      end,
      send_input = function() end,
    }

    package.loaded['claude.rules'] = {
      build_init_prompt = function() return nil end,
    }

    vim.fn.executable = function() return 1 end
    require('claude.config').setup({ cli_args = {} })
    persistence = require('claude.persistence')
  end)

  describe('create with session_id', function()
    it('generates a session_id and passes --session-id to terminal', function()
      session = require('claude.session')
      local s = session.create('test')
      assert.is_string(s.session_id)
      assert.truthy(s.session_id:match('^%x+%-'))
      assert.truthy(vim.tbl_contains(captured_args, '--session-id'))
      assert.truthy(vim.tbl_contains(captured_args, s.session_id))
    end)

    it('prepends cli_args before --session-id', function()
      package.loaded['claude.config'] = nil
      require('claude.config').setup({ cli_args = { '--permission-mode', 'plan' } })
      package.loaded['claude.session'] = nil
      session = require('claude.session')
      local s = session.create('test')
      assert.equals('--permission-mode', captured_args[1])
      assert.equals('plan', captured_args[2])
      assert.equals('--session-id', captured_args[3])
      assert.equals(s.session_id, captured_args[4])
    end)
  end)
end)
