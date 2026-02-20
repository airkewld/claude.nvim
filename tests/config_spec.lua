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

  it('defaults enforce_claude_md to true', function()
    config.setup({})
    local cfg = config.get()
    assert.is_true(cfg.enforce_claude_md)
  end)

  it('allows user to disable enforce_claude_md', function()
    config.setup({ enforce_claude_md = false })
    local cfg = config.get()
    assert.is_false(cfg.enforce_claude_md)
  end)

  it('defaults claude_md_paths to standard locations', function()
    config.setup({})
    local cfg = config.get()
    assert.equals(3, #cfg.claude_md_paths)
    assert.equals('~/.claude/CLAUDE.md', cfg.claude_md_paths[1][1])
    assert.equals('CLAUDE.md', cfg.claude_md_paths[2][1])
    assert.equals('.claude/CLAUDE.md', cfg.claude_md_paths[3][1])
  end)

  it('allows user to override claude_md_paths', function()
    config.setup({ claude_md_paths = {
      { '/custom/rules.md', 'Custom rules' },
    }})
    local cfg = config.get()
    assert.equals(1, #cfg.claude_md_paths)
    assert.equals('/custom/rules.md', cfg.claude_md_paths[1][1])
  end)
end)
