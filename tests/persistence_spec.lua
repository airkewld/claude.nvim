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

    it('returns nil on corrupt file', function()
      local path = tmpdir .. '/' .. persistence.encode_path(vim.fn.getcwd()) .. '.json'
      local f = io.open(path, 'w')
      f:write('not valid json{{{')
      f:close()

      local loaded = persistence.load()
      assert.is_nil(loaded)
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
end)
