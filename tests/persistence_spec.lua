-- ABOUTME: Tests for persistence module (UUID, path encoding, JSON save/load)
-- ABOUTME: Validates session state survives across Neovim restarts

describe('persistence', function()
  local persistence

  before_each(function()
    package.loaded['claude.persistence'] = nil
    persistence = require('claude.persistence')
  end)

  describe('generate_session_id', function()
    it('returns a string matching UUID v4 format', function()
      local id = persistence.generate_session_id()
      assert.is_string(id)
      assert.truthy(id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'))
    end)

    it('returns unique values on successive calls', function()
      local seen = {}
      for _ = 1, 100 do
        local id = persistence.generate_session_id()
        assert.is_nil(seen[id], 'duplicate UUID generated')
        seen[id] = true
      end
    end)
  end)

  describe('encode_path', function()
    it('replaces path separators with dashes', function()
      local result = persistence.encode_path('/Users/oscar/dev/myproject')
      assert.equals('-Users-oscar-dev-myproject', result)
    end)

    it('handles trailing slashes', function()
      local result = persistence.encode_path('/Users/oscar/dev/myproject/')
      assert.equals('-Users-oscar-dev-myproject-', result)
    end)
  end)

  describe('decode_path', function()
    it('reconstructs a simple path with no hyphens', function()
      local tmproot = vim.fn.tempname()
      vim.fn.mkdir(tmproot .. '/aaa/bbb/ccc', 'p')
      local encoded = persistence.encode_path(tmproot .. '/aaa/bbb/ccc')
      local decoded = persistence.decode_path(encoded)
      assert.equals(tmproot .. '/aaa/bbb/ccc', decoded)
      vim.fn.delete(tmproot, 'rf')
    end)

    it('handles hyphens in directory names', function()
      local tmproot = vim.fn.tempname()
      vim.fn.mkdir(tmproot .. '/my-project/src', 'p')
      local encoded = persistence.encode_path(tmproot .. '/my-project/src')
      local decoded = persistence.decode_path(encoded)
      assert.equals(tmproot .. '/my-project/src', decoded)
      vim.fn.delete(tmproot, 'rf')
    end)

    it('returns nil when directory does not exist', function()
      local decoded = persistence.decode_path('-nonexistent-fake-path-xyz')
      assert.is_nil(decoded)
    end)
  end)

  describe('get_storage_dir', function()
    it('returns a path under stdpath data', function()
      local dir = persistence.get_storage_dir()
      local data = vim.fn.stdpath('data')
      assert.truthy(dir:find(data, 1, true))
      assert.truthy(dir:find('claude%-nvim', 1))
    end)
  end)

  describe('save and load', function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      persistence._set_storage_dir(tmpdir)
    end)

    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('round-trips session data', function()
      local data = {
        sessions = {
          { name = 'session-1', session_id = 'abc-123' },
          { name = 'session-2', session_id = 'def-456' },
        },
        active = 1,
        counter = 2,
      }
      persistence.save(data)
      local loaded = persistence.load()
      assert.same(data, loaded)
    end)

    it('returns nil when no file exists', function()
      local loaded = persistence.load()
      assert.is_nil(loaded)
    end)

    it('returns nil on corrupt file without re-migrating', function()
      -- Write an old per-CWD file that migration would find
      local old = io.open(tmpdir .. '/-some-project.json', 'w')
      old:write(vim.fn.json_encode({
        sessions = { { name = 'old-session', session_id = 'x' } },
        active = 1,
        counter = 1,
      }))
      old:close()

      -- Write a corrupt sessions.json
      local path = tmpdir .. '/sessions.json'
      local f = io.open(path, 'w')
      f:write('not valid json{{{')
      f:close()

      -- Should return nil, NOT migrate from old files
      local loaded = persistence.load()
      assert.is_nil(loaded)

      -- sessions.json should still be corrupt (not overwritten by migration)
      local check = io.open(path, 'r')
      local content = check:read('*a')
      check:close()
      assert.equals('not valid json{{{', content)
    end)

    it('creates storage directory if it does not exist', function()
      vim.fn.delete(tmpdir, 'rf')
      local data = {
        sessions = { { name = 's1', session_id = 'x' } },
        active = 1,
        counter = 1,
      }
      persistence.save(data)
      local loaded = persistence.load()
      assert.same(data, loaded)
    end)
  end)

  describe('migrate', function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      persistence._set_storage_dir(tmpdir)
    end)

    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('merges old per-cwd files into global sessions.json', function()
      local cwd = vim.fn.getcwd()
      local encoded = persistence.encode_path(cwd)
      local old_file = tmpdir .. '/' .. encoded .. '.json'
      local f = io.open(old_file, 'w')
      f:write(vim.fn.json_encode({
        sessions = {
          { name = 'old-session', session_id = 'abc-123' },
        },
        active = 1,
        counter = 1,
      }))
      f:close()

      local data = persistence.load()
      assert.is_not_nil(data)
      assert.equals(1, #data.sessions)
      assert.equals('old-session', data.sessions[1].name)
      assert.equals('abc-123', data.sessions[1].session_id)
      assert.equals(cwd, data.sessions[1].cwd)
    end)

    it('merges sessions from multiple old files', function()
      local cwd = vim.fn.getcwd()
      local encoded1 = persistence.encode_path(cwd)
      local f1 = io.open(tmpdir .. '/' .. encoded1 .. '.json', 'w')
      f1:write(vim.fn.json_encode({
        sessions = { { name = 'proj1-session', session_id = 'id-1' } },
        active = 1,
        counter = 1,
      }))
      f1:close()

      local f2 = io.open(tmpdir .. '/-fake-other-project.json', 'w')
      f2:write(vim.fn.json_encode({
        sessions = { { name = 'proj2-session', session_id = 'id-2' } },
        active = 1,
        counter = 1,
      }))
      f2:close()

      local data = persistence.load()
      assert.is_not_nil(data)
      assert.equals(2, #data.sessions)
    end)

    it('skips corrupt old files during migration', function()
      local f = io.open(tmpdir .. '/-some-project.json', 'w')
      f:write('not valid json{{{')
      f:close()

      local data = persistence.load()
      assert.is_nil(data)
    end)

    it('does not re-migrate once sessions.json exists', function()
      local f = io.open(tmpdir .. '/-old-project.json', 'w')
      f:write(vim.fn.json_encode({
        sessions = { { name = 'should-not-appear', session_id = 'x' } },
        active = 1,
        counter = 1,
      }))
      f:close()

      persistence.save({
        sessions = { { name = 'current', session_id = 'y' } },
        active = 1,
        counter = 1,
      })

      local data = persistence.load()
      assert.equals(1, #data.sessions)
      assert.equals('current', data.sessions[1].name)
    end)
  end)
end)
