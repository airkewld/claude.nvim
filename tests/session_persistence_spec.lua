-- ABOUTME: Tests for session persistence integration
-- ABOUTME: Validates session_id assignment, dormant sessions, save/load/resume

describe('session persistence', function()
  local session
  local persistence
  local captured_args
  local tmpdir

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

    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    persistence._set_storage_dir(tmpdir)
  end)

  after_each(function()
    if tmpdir then vim.fn.delete(tmpdir, 'rf') end
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

  describe('is_dormant', function()
    it('returns true for sessions with nil bufnr', function()
      session = require('claude.session')
      local dormant = { name = 'old', session_id = 'abc', bufnr = nil }
      assert.is_true(session.is_dormant(dormant))
    end)

    it('returns false for active sessions', function()
      session = require('claude.session')
      local s = session.create('active')
      assert.is_false(session.is_dormant(s))
    end)
  end)

  describe('cwd tracking', function()
    it('captures cwd at creation time', function()
      session = require('claude.session')
      local s = session.create('test')
      assert.equals(vim.fn.getcwd(), s.cwd)
    end)

    it('persists cwd through save and load', function()
      session = require('claude.session')
      session.create('test')
      session.save_state()

      local data = persistence.load()
      assert.equals(vim.fn.getcwd(), data.sessions[1].cwd)
    end)

    it('restores cwd on dormant sessions after restart', function()
      session = require('claude.session')
      session.create('test')
      session.save_state()

      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      assert.equals(vim.fn.getcwd(), session.list()[1].cwd)
    end)
  end)

  describe('save_state and load_state', function()
    it('persists session names, ids, active, and counter', function()
      session = require('claude.session')
      local s1 = session.create('alpha')
      local s2 = session.create('beta')
      session.save_state()

      local data = persistence.load()
      assert.equals(2, #data.sessions)
      assert.equals('alpha', data.sessions[1].name)
      assert.equals(s1.session_id, data.sessions[1].session_id)
      assert.equals('beta', data.sessions[2].name)
      assert.equals(s2.session_id, data.sessions[2].session_id)
      assert.equals(2, data.active)
    end)

    it('restores dormant sessions after simulated restart', function()
      session = require('claude.session')
      session.create('alpha')
      session.create('beta')
      session.save_state()

      -- Simulate restart
      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      assert.equals(2, session.count())
      local sessions = session.list()
      assert.equals('alpha', sessions[1].name)
      assert.is_nil(sessions[1].bufnr)
      assert.is_true(session.is_dormant(sessions[1]))
      assert.equals('beta', sessions[2].name)
      assert.is_true(session.is_dormant(sessions[2]))
      assert.equals(2, session.active_index())
    end)

    it('does nothing when no saved data exists', function()
      session = require('claude.session')
      persistence._set_storage_dir(vim.fn.tempname()) -- nonexistent dir
      session.load_state()
      assert.equals(0, session.count())
    end)

    it('sets init_prompt_sent to true for restored sessions', function()
      session = require('claude.session')
      session.create('test')
      session.save_state()

      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      local s = session.list()[1]
      assert.is_true(s.init_prompt_sent)
    end)
  end)

  describe('auto-save', function()
    it('auto-saves after create', function()
      session = require('claude.session')
      session.create('test')
      local data = persistence.load()
      assert.equals(1, #data.sessions)
    end)

    it('auto-saves after remove', function()
      session = require('claude.session')
      session.create('a')
      session.create('b')
      session.remove(1)
      local data = persistence.load()
      assert.equals(1, #data.sessions)
      assert.equals('b', data.sessions[1].name)
    end)

    it('auto-saves after rename', function()
      session = require('claude.session')
      session.create('old-name')
      session.rename(1, 'new-name')
      local data = persistence.load()
      assert.equals('new-name', data.sessions[1].name)
    end)

    it('auto-saves after swap', function()
      session = require('claude.session')
      session.create('first')
      session.create('second')
      session.swap(1, 2)
      local data = persistence.load()
      assert.equals('second', data.sessions[1].name)
      assert.equals('first', data.sessions[2].name)
    end)
  end)

  describe('resume', function()
    it('spawns with --resume and populates bufnr/job_id', function()
      session = require('claude.session')
      session.create('saved')
      local original_id = session.list()[1].session_id
      session.save_state()

      -- Simulate restart
      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      assert.is_true(session.is_dormant(session.list()[1]))

      session.resume(1)

      local s = session.list()[1]
      assert.is_false(session.is_dormant(s))
      assert.is_not_nil(s.bufnr)
      assert.is_not_nil(s.job_id)
      assert.is_true(s.is_alive)
      assert.is_true(s.init_prompt_sent)
      assert.truthy(vim.tbl_contains(captured_args, '--resume'))
      assert.truthy(vim.tbl_contains(captured_args, original_id))
    end)

    it('preserves original cwd on resume for CLI project lookup', function()
      session = require('claude.session')
      session.create('remote')
      local s = session.list()[1]
      s.cwd = '/some/original/dir'
      session.save_state()

      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      assert.equals('/some/original/dir', session.list()[1].cwd)

      session.resume(1)

      assert.equals('/some/original/dir', session.list()[1].cwd)
    end)

    it('sets resuming flag for failed resume detection', function()
      session = require('claude.session')
      session.create('stale')
      session.save_state()

      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      session.resume(1)
      local s = session.list()[1]
      assert.is_true(s.resuming)
    end)

    it('keeps session visible as exited on failed resume', function()
      session = require('claude.session')
      session.create('stale')
      session.save_state()

      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      session.resume(1)
      local s = session.list()[1]
      local bufnr = s.bufnr

      session.on_exit(bufnr, 1)
      assert.equals(1, session.count())
      assert.is_false(session.list()[1].is_alive)
    end)

    it('does nothing for non-dormant sessions', function()
      session = require('claude.session')
      local s = session.create('active')
      local original_bufnr = s.bufnr
      session.resume(1)
      assert.equals(original_bufnr, session.list()[1].bufnr)
    end)
  end)

  describe('remove dormant', function()
    it('removes dormant sessions without buffer errors', function()
      session = require('claude.session')
      session.create('saved')
      session.save_state()

      -- Simulate restart
      package.loaded['claude.session'] = nil
      session = require('claude.session')
      session.load_state()

      assert.equals(1, session.count())
      session.remove(1)
      assert.equals(0, session.count())

      -- Verify auto-save after remove
      local data = persistence.load()
      assert.equals(0, #data.sessions)
    end)
  end)

  describe('cross-instance visibility', function()
    it('refresh_state picks up sessions written to disk by another instance', function()
      session = require('claude.session')
      session.create('local-session')

      -- Simulate another instance writing a new session to disk
      persistence.save({
        sessions = {
          { name = 'local-session', session_id = session.list()[1].session_id, cwd = vim.fn.getcwd() },
          { name = 'remote-session', session_id = 'remote-uuid-123', cwd = '/other/project' },
        },
        active = 1,
        counter = 2,
      })

      session.refresh_state()

      assert.equals(2, session.count())
      assert.equals('local-session', session.list()[1].name)
      assert.equals('remote-session', session.list()[2].name)
    end)

    it('refresh_state preserves runtime state of locally running sessions', function()
      session = require('claude.session')
      local s = session.create('running')
      local original_bufnr = s.bufnr
      local original_job_id = s.job_id

      -- Simulate another instance adding a session to disk
      persistence.save({
        sessions = {
          { name = 'running', session_id = s.session_id, cwd = vim.fn.getcwd() },
          { name = 'other', session_id = 'other-uuid', cwd = '/somewhere' },
        },
        active = 1,
        counter = 2,
      })

      session.refresh_state()

      local refreshed = session.list()[1]
      assert.equals(original_bufnr, refreshed.bufnr)
      assert.equals(original_job_id, refreshed.job_id)
      assert.is_true(refreshed.is_alive)
    end)

    it('save_state merges with sessions from other instances', function()
      session = require('claude.session')
      session.create('mine')

      -- Another instance wrote a session to disk
      local my_id = session.list()[1].session_id
      persistence.save({
        sessions = {
          { name = 'mine', session_id = my_id, cwd = vim.fn.getcwd() },
          { name = 'theirs', session_id = 'their-uuid', cwd = '/their/project' },
        },
        active = 1,
        counter = 2,
      })

      -- Local save should not overwrite the other instance's session
      session.save_state()
      local data = persistence.load()
      assert.equals(2, #data.sessions)

      local names = {}
      for _, s in ipairs(data.sessions) do
        names[s.name] = true
      end
      assert.is_true(names['mine'])
      assert.is_true(names['theirs'])
    end)
  end)
end)
