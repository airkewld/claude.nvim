-- ABOUTME: Tests smart_join, which rejoins terminal wrap-induced line breaks
-- ABOUTME: Full-width lines are continuations; shorter lines end a logical line

describe('terminal.smart_join', function()
  local terminal

  before_each(function()
    package.loaded['claude.terminal'] = nil
    terminal = require('claude.terminal')
  end)

  it('returns a single line unchanged', function()
    assert.equals('kubectl get pods', terminal.smart_join({ 'kubectl get pods' }, 80))
  end)

  it('joins two full-width lines with no separator', function()
    local lines = { string.rep('a', 10), 'bcdef' }
    assert.equals(string.rep('a', 10) .. 'bcdef', terminal.smart_join(lines, 10))
  end)

  it('preserves a genuine newline after a short line', function()
    local lines = { 'echo one', 'echo two' }
    assert.equals('echo one\necho two', terminal.smart_join(lines, 80))
  end)

  it('rejoins a wrapped command but keeps a following separate line', function()
    -- width 20: the command fills the first row, wraps, then a short echo line
    local lines = { 'kubectl get pods --n', 'amespace default', 'echo done' }
    assert.equals('kubectl get pods --namespace default\necho done', terminal.smart_join(lines, 20))
  end)

  it('collapses three consecutive full-width rows into one line', function()
    local lines = { string.rep('x', 5), string.rep('y', 5), 'zz' }
    assert.equals(string.rep('x', 5) .. string.rep('y', 5) .. 'zz', terminal.smart_join(lines, 5))
  end)
end)
