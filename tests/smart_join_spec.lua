-- ABOUTME: Tests smart_join, which collapses wrapped terminal lines into
-- ABOUTME: shell-pasteable text, keeping blank lines as breaks between blocks

describe('terminal.smart_join', function()
  local terminal

  before_each(function()
    package.loaded['claude.terminal'] = nil
    terminal = require('claude.terminal')
  end)

  it('trims a single line', function()
    assert.equals('kubectl get pods', terminal.smart_join({ '  kubectl get pods  ' }))
  end)

  it('joins wrapped rows into one line with a single space', function()
    local lines = { '  kubectl get pods --output', '  wide' }
    assert.equals('kubectl get pods --output wide', terminal.smart_join(lines))
  end)

  it('strips trailing padding before joining', function()
    local lines = { 'echo foo                 ', 'echo bar' }
    assert.equals('echo foo echo bar', terminal.smart_join(lines))
  end)

  it('keeps a blank line as a break between blocks', function()
    local lines = { 'cmd one --flag', 'continues here', '', 'cmd two' }
    assert.equals('cmd one --flag continues here\ncmd two', terminal.smart_join(lines))
  end)

  it('collapses consecutive blank lines into a single break', function()
    local lines = { 'a', '', '   ', 'b' }
    assert.equals('a\nb', terminal.smart_join(lines))
  end)

  it('ignores leading and trailing blank lines', function()
    local lines = { '', 'a', 'b', '' }
    assert.equals('a b', terminal.smart_join(lines))
  end)

  it('returns empty string for an all-blank selection', function()
    assert.equals('', terminal.smart_join({ '', '   ' }))
  end)
end)
