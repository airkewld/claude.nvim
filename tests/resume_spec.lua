-- ABOUTME: Tests the resume launcher that opens Claude's native --resume picker
-- ABOUTME: Verifies it spawns a session and labels it once the session settles

describe('resume.open', function()
  local resume
  local created
  local switched

  before_each(function()
    created = nil
    switched = false

    for _, mod in ipairs({
      'claude', 'claude.resume', 'claude.session', 'claude.config',
      'claude.history', 'claude.window',
    }) do
      package.loaded[mod] = nil
    end

    package.loaded['claude.session'] = {
      create = function(name, args, opts)
        created = { name = name, args = args, opts = opts }
        return created
      end,
      get_winnr = function() return nil end,
      get_active = function() return nil end,
    }
    package.loaded['claude'] = {
      switch_to_active = function() switched = true end,
    }

    resume = require('claude.resume')
  end)

  it('spawns a session running claude --resume in the current project', function()
    resume.open()
    assert.same({ '--resume' }, created.args)
    assert.is_nil(created.name)
    assert.equals(vim.fn.getcwd(), created.opts.cwd)
    assert.is_true(switched)
  end)

  it('registers a settle callback to resolve the resumed name', function()
    resume.open()
    assert.equals('function', type(created.on_settled))
  end)

  it('does not switch when session.create returns nil', function()
    package.loaded['claude.session'].create = function() return nil end
    resume.open()
    assert.is_false(switched)
  end)
end)

describe('resume._resolve_name', function()
  local resume

  before_each(function()
    for _, mod in ipairs({
      'claude', 'claude.resume', 'claude.session', 'claude.config',
      'claude.history', 'claude.window',
    }) do
      package.loaded[mod] = nil
    end
    package.loaded['claude.session'] = {
      get_winnr = function() return nil end,
      get_active = function() return nil end,
    }
    resume = require('claude.resume')
  end)

  it('renames the session to the newest transcript agent name', function()
    package.loaded['claude.history'] = {
      list = function() return {} end,
      filter_by_cwd = function()
        return {
          { id = 'xyz', name = 'cool-agent', mtime = 2 },
          { id = 'old', name = 'stale', mtime = 1 },
        }
      end,
    }
    local s = { name = 'session-1', cwd = '/proj' }
    resume._resolve_name(s)
    assert.equals('cool-agent', s.name)
    assert.equals('xyz', s.resume_id)
  end)

  it('keeps the placeholder name when the newest transcript has no name', function()
    package.loaded['claude.history'] = {
      list = function() return {} end,
      filter_by_cwd = function()
        return { { id = 'xyz', name = nil, mtime = 2 } }
      end,
    }
    local s = { name = 'session-1', cwd = '/proj' }
    resume._resolve_name(s)
    assert.equals('session-1', s.name)
    assert.equals('xyz', s.resume_id)
  end)

  it('does nothing when there are no transcripts for the project', function()
    package.loaded['claude.history'] = {
      list = function() return {} end,
      filter_by_cwd = function() return {} end,
    }
    local s = { name = 'session-1', cwd = '/proj' }
    resume._resolve_name(s)
    assert.equals('session-1', s.name)
    assert.is_nil(s.resume_id)
  end)
end)
