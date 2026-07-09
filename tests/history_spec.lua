-- ABOUTME: Tests for reading past Claude CLI sessions from ~/.claude/projects
-- ABOUTME: Covers JSONL head parsing, directory scanning, and cwd filtering

describe('history._parse_lines', function()
  local history

  before_each(function()
    package.loaded['claude.history'] = nil
    history = require('claude.history')
  end)

  local function user_line(content, extra)
    local entry = {
      type = 'user',
      message = { role = 'user', content = content },
      cwd = '/proj',
      timestamp = '2026-07-09T15:32:52.434Z',
    }
    for k, v in pairs(extra or {}) do
      entry[k] = v
    end
    return vim.json.encode(entry)
  end

  it('returns title and cwd from the first user entry', function()
    local head = history._parse_lines({
      '{"type":"last-prompt","leafUuid":"x","sessionId":"y"}',
      '{"type":"permission-mode","permissionMode":"plan","sessionId":"y"}',
      user_line('fix the login bug'),
    })
    assert.equals('fix the login bug', head.title)
    assert.equals('/proj', head.cwd)
  end)

  it('skips user entries with non-string content', function()
    local head = history._parse_lines({
      user_line({ { type = 'tool_result', content = 'stuff' } }),
      user_line('real prompt'),
    })
    assert.equals('real prompt', head.title)
  end)

  it('skips meta user entries', function()
    local head = history._parse_lines({
      user_line('synthetic', { isMeta = true }),
      user_line('typed by a human'),
    })
    assert.equals('typed by a human', head.title)
  end)

  it('skips unparseable lines without erroring', function()
    local head = history._parse_lines({
      'not json{{{',
      user_line('still works'),
    })
    assert.equals('still works', head.title)
  end)

  it('returns empty result when nothing qualifies', function()
    local head = history._parse_lines({
      '{"type":"last-prompt"}',
      'garbage',
    })
    assert.is_nil(head.title)
    assert.is_nil(head.cwd)
  end)

  it('flattens newlines and trims whitespace in titles', function()
    local head = history._parse_lines({
      user_line('  line one\nline two\n'),
    })
    assert.equals('line one line two', head.title)
  end)
end)
