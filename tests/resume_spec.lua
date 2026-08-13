-- ABOUTME: Tests the resume launcher that opens Claude's native --resume picker
-- ABOUTME: Verifies it spawns a session terminal in the current project

describe('resume.open', function()
  local resume
  local created
  local switched

  before_each(function()
    created = nil
    switched = false

    for _, mod in ipairs({ 'claude', 'claude.resume', 'claude.session', 'claude.config' }) do
      package.loaded[mod] = nil
    end

    package.loaded['claude.session'] = {
      create = function(name, args, opts)
        created = { name = name, args = args, opts = opts }
        return created
      end,
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

  it('does not switch when session.create returns nil', function()
    package.loaded['claude.session'].create = function() return nil end
    resume.open()
    assert.is_false(switched)
  end)
end)
