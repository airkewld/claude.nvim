-- ABOUTME: Tests that session sends CLAUDE.md rules on first idle
-- ABOUTME: Validates enforce_claude_md config flag and one-shot behavior

describe('session init prompt', function()
  local session
  local config
  local sent_text
  local sent_job_id

  before_each(function()
    sent_text = nil
    sent_job_id = nil

    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.terminal'] = nil
    package.loaded['claude.rules'] = nil

    package.loaded['claude.terminal'] = {
      create = function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        return bufnr, 42
      end,
      send_input = function(job_id, text)
        sent_job_id = job_id
        sent_text = text
      end,
    }

    package.loaded['claude.rules'] = {
      build_init_prompt = function() return 'test rules prompt' end,
    }

    vim.fn.executable = function() return 1 end
    config = require('claude.config')
  end)

  it('sends init prompt on first idle call', function()
    config.setup({ enforce_claude_md = true })
    session = require('claude.session')

    local s = session.create('test')
    session._handle_idle(s)

    assert.equals('test rules prompt', sent_text)
    assert.equals(42, sent_job_id)
  end)

  it('sends init prompt only once', function()
    config.setup({ enforce_claude_md = true })
    session = require('claude.session')

    local s = session.create('test')
    session._handle_idle(s)
    assert.equals('test rules prompt', sent_text)

    sent_text = nil
    session._handle_idle(s)
    assert.is_nil(sent_text)
  end)

  it('does not send when enforce_claude_md is false', function()
    config.setup({ enforce_claude_md = false })
    session = require('claude.session')

    local s = session.create('test')
    session._handle_idle(s)

    assert.is_nil(sent_text)
  end)

  it('does not send when build_init_prompt returns nil', function()
    config.setup({ enforce_claude_md = true })

    package.loaded['claude.rules'] = {
      build_init_prompt = function() return nil end,
    }

    session = require('claude.session')
    local s = session.create('test')
    session._handle_idle(s)

    assert.is_nil(sent_text)
  end)
end)
