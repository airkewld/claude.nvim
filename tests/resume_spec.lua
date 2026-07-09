-- ABOUTME: Tests for the resume picker over past Claude CLI sessions
-- ABOUTME: Covers row layout, tab filtering, and the resume action

local function entry(id, title, cwd, mtime)
  return { id = id, title = title, cwd = cwd, mtime = mtime or os.time() }
end

describe('resume rows and tabs', function()
  local resume

  before_each(function()
    package.loaded['claude.resume'] = nil
    package.loaded['claude.history'] = nil
    package.loaded['claude.menu'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.config'] = nil

    package.loaded['claude.session'] = {
      list = function() return {} end,
      active_index = function() return 0 end,
    }

    require('claude.config').setup({})
    resume = require('claude.resume')
  end)

  describe('build_rows', function()
    it('aligns the cwd column across rows with mixed-length titles', function()
      local entries = {
        entry('a', 'short', vim.env.HOME .. '/a'),
        entry('b', 'a much longer first prompt here', vim.env.HOME .. '/b'),
        entry('c', 'mid-length title', vim.env.HOME .. '/c'),
      }
      local lines = resume._build_rows(entries, os.time(), 120)
      assert.equals(#entries, #lines)

      local first_offset = lines[1]:find('~', 1, true)
      assert.is_number(first_offset)
      for i = 2, #lines do
        assert.equals(first_offset, lines[i]:find('~', 1, true),
          'row ' .. i .. ' cwd offset mismatch: ' .. lines[i])
      end
    end)

    it('right-aligns the index column when the list has 10+ entries', function()
      local entries = {}
      for i = 1, 12 do
        table.insert(entries, entry('id' .. i, 't' .. i, vim.env.HOME .. '/p'))
      end
      local lines = resume._build_rows(entries, os.time(), 120)
      assert.truthy(lines[9]:match('^ +9 '), 'row 9 expected " 9" padding, got: ' .. lines[9])
      assert.truthy(lines[10]:match('^ *10 '), 'row 10 expected "10", got: ' .. lines[10])
      local p9 = lines[9]:find('t9', 1, true)
      local p10 = lines[10]:find('t10', 1, true)
      assert.equals(p9, p10)
    end)

    it('ends rows with the activity column', function()
      local ts = os.time()
      local lines = resume._build_rows({ entry('a', 'only', vim.env.HOME .. '/a', ts) }, ts, 120)
      local expected = require('claude.menu').format_activity(ts, ts)
      assert.truthy(lines[1]:sub(- #expected) == expected,
        'expected row to end with "' .. expected .. '", got: ' .. lines[1])
    end)

    it('truncates long titles with an ellipsis to fit the width', function()
      local long_title = string.rep('word ', 40)
      local entries = {
        entry('a', long_title, vim.env.HOME .. '/a'),
        entry('b', 'short', vim.env.HOME .. '/b'),
      }
      local width = 60
      local lines = resume._build_rows(entries, os.time(), width)
      for i, line in ipairs(lines) do
        assert.is_true(vim.fn.strdisplaywidth(line) <= width,
          'row ' .. i .. ' wider than ' .. width .. ': ' .. line)
      end
      assert.truthy(lines[1]:find('…', 1, true), 'expected ellipsis in: ' .. lines[1])
    end)
  end)

  describe('visible', function()
    it('filters by cwd on the project tab', function()
      local entries = {
        entry('a', 't', '/proj/a'),
        entry('b', 't', '/proj/b'),
      }
      local visible = resume._visible(entries, 'project', '/proj/a')
      assert.equals(1, #visible)
      assert.equals('a', visible[1].id)
    end)

    it('passes all entries through on the all tab', function()
      local entries = {
        entry('a', 't', '/proj/a'),
        entry('b', 't', '/proj/b'),
      }
      local visible = resume._visible(entries, 'all', '/proj/a')
      assert.equals(2, #visible)
    end)
  end)
end)

describe('resume._resume_entry', function()
  local resume
  local created
  local switched
  local activated
  local fake_sessions
  local create_result

  before_each(function()
    created = nil
    switched = false
    activated = nil
    fake_sessions = {}
    create_result = {}

    package.loaded['claude.resume'] = nil
    package.loaded['claude.history'] = nil
    package.loaded['claude.menu'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.config'] = nil
    package.loaded['claude'] = nil

    package.loaded['claude.session'] = {
      list = function() return fake_sessions end,
      set_active = function(i) activated = i end,
      create = function(name, args, opts)
        created = { name = name, args = args, opts = opts }
        return create_result
      end,
    }
    package.loaded['claude'] = {
      switch_to_active = function() switched = true end,
    }

    require('claude.config').setup({})
    resume = require('claude.resume')
  end)

  it('creates a session with --resume and the entry cwd', function()
    resume._resume_entry({ id = 'abc-123', cwd = '/proj', title = 't' })
    assert.same({ '--resume', 'abc-123' }, created.args)
    assert.equals('/proj', created.opts.cwd)
    assert.equals('abc-123', create_result.resume_id)
    assert.is_true(switched)
  end)

  it('re-activates a live session already resumed from the same id', function()
    fake_sessions = {
      { name = 'other', resume_id = 'zzz', is_alive = true },
      { name = 'mine', resume_id = 'abc-123', is_alive = true },
    }
    resume._resume_entry({ id = 'abc-123', cwd = '/proj', title = 't' })
    assert.is_nil(created)
    assert.equals(2, activated)
    assert.is_true(switched)
  end)

  it('spawns a fresh session when the previous resume has exited', function()
    fake_sessions = {
      { name = 'mine', resume_id = 'abc-123', is_alive = false },
    }
    resume._resume_entry({ id = 'abc-123', cwd = '/proj', title = 't' })
    assert.is_not_nil(created)
  end)

  it('tolerates session.create returning nil', function()
    create_result = nil
    assert.has_no_error(function()
      resume._resume_entry({ id = 'abc-123', cwd = '/proj', title = 't' })
    end)
    assert.is_false(switched)
  end)
end)
