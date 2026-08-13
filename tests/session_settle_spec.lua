-- ABOUTME: Tests that a session's on_settled callback fires once on first idle
-- ABOUTME: Resume uses this to label the resumed session after it finishes replaying

describe('session on_settled', function()
  local session

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
    require('claude.config').setup({})
    session = require('claude.session')
  end)

  it('invokes on_settled on the first idle and only once', function()
    local calls = 0
    local s = session.create('test')
    s.on_settled = function() calls = calls + 1 end
    session._handle_idle(s)
    session._handle_idle(s)
    assert.equals(1, calls)
  end)

  it('does not invoke on_settled when the session is dead', function()
    local calls = 0
    local s = session.create('test')
    s.is_alive = false
    s.on_settled = function() calls = calls + 1 end
    session._handle_idle(s)
    assert.equals(0, calls)
  end)
end)
