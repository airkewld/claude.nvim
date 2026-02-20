-- ABOUTME: Tests for config module defaults and user overrides
-- ABOUTME: Validates cli_args default and merge behavior

describe('config', function()
  local config

  before_each(function()
    package.loaded['claude.config'] = nil
    config = require('claude.config')
  end)

  it('defaults cli_args to plan permission mode', function()
    config.setup({})
    local cfg = config.get()
    assert.same({ '--permission-mode', 'plan' }, cfg.cli_args)
  end)

  it('allows user to override cli_args', function()
    config.setup({ cli_args = {} })
    local cfg = config.get()
    assert.same({}, cfg.cli_args)
  end)

  it('allows user to set custom cli_args', function()
    config.setup({ cli_args = { '--verbose' } })
    local cfg = config.get()
    assert.same({ '--verbose' }, cfg.cli_args)
  end)
end)
