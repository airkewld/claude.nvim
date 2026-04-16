-- ABOUTME: Tests for per-session user-idle tracking that drives auto-review
-- ABOUTME: Covers mark_input, is_idle predicate, and the auto_review_timeout_ms config

describe('auto review', function()
  local session
  local config

  before_each(function()
    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.terminal'] = nil
    package.loaded['claude.rules'] = nil

    package.loaded['claude.terminal'] = {
      create = function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        return bufnr, 42
      end,
      send_input = function() end,
    }

    package.loaded['claude.rules'] = {
      build_init_prompt = function() return nil end,
    }

    vim.fn.executable = function() return 1 end
    config = require('claude.config')
    config.setup({})
    session = require('claude.session')
  end)

  it('defaults auto_review_timeout_ms to 10 minutes', function()
    assert.equals(600000, config.get().auto_review_timeout_ms)
  end)

  it('initializes last_input_at on create', function()
    local s = session.create('test')
    assert.is_number(s.last_input_at)
  end)

  it('mark_input bumps last_input_at to now', function()
    local s = session.create('test')
    s.last_input_at = 0
    session.mark_input(s)
    assert.is_true(s.last_input_at > 0)
  end)

  it('is_idle returns false immediately after input', function()
    local s = session.create('test')
    session.mark_input(s)
    assert.is_false(session.is_idle(s, s.last_input_at, 600000))
  end)

  it('is_idle returns true once threshold has elapsed', function()
    local s = session.create('test')
    s.last_input_at = 1000
    assert.is_true(session.is_idle(s, 1000 + 600000, 600000))
  end)

  it('is_idle returns false when threshold is 0', function()
    local s = session.create('test')
    s.last_input_at = 0
    assert.is_false(session.is_idle(s, 10000000, 0))
  end)

  it('is_idle returns false when threshold is false', function()
    local s = session.create('test')
    s.last_input_at = 0
    assert.is_false(session.is_idle(s, 10000000, false))
  end)
end)
