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

  it('skips slash-command entries and uses the next real message', function()
    local head = history._parse_lines({
      user_line('<command-name>/clear</command-name> <command-message>clear</command-message>'),
      user_line('the real prompt'),
    })
    assert.equals('the real prompt', head.title)
    assert.equals('/proj', head.cwd)
  end)

  it('flags command-only transcripts and still captures cwd', function()
    local head = history._parse_lines({
      user_line('<command-name>/clear</command-name> <command-message>clear</command-message>'),
    })
    assert.is_true(head.command_only)
    assert.equals('/proj', head.cwd)
    assert.is_nil(head.title)
  end)
end)

describe('history._parse_name', function()
  local history

  before_each(function()
    package.loaded['claude.history'] = nil
    history = require('claude.history')
  end)

  local function name_line(name)
    return vim.json.encode({ type = 'agent-name', agentName = name, sessionId = 'x' })
  end

  it('returns the last agent-name in the given lines', function()
    local name = history._parse_name({
      name_line('first-name'),
      '{"type":"assistant","message":{}}',
      name_line('renamed-later'),
    })
    assert.equals('renamed-later', name)
  end)

  it('returns nil when no agent-name is present', function()
    assert.is_nil(history._parse_name({
      '{"type":"user","message":{}}',
      'garbage',
    }))
  end)

  it('skips unparseable lines without erroring', function()
    local name = history._parse_name({
      'not json{{{',
      name_line('good-name'),
      'more garbage',
    })
    assert.equals('good-name', name)
  end)
end)

describe('history.list', function()
  local history
  local root

  local function jsonl_line(title, cwd)
    return vim.json.encode({
      type = 'user',
      message = { role = 'user', content = title },
      cwd = cwd,
    })
  end

  local function write_file(path, lines)
    local fh = assert(io.open(path, 'w'))
    fh:write(table.concat(lines, '\n'), '\n')
    fh:close()
  end

  before_each(function()
    package.loaded['claude.history'] = nil
    history = require('claude.history')

    root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/-proj-a', 'p')
    vim.fn.mkdir(root .. '/-proj-b', 'p')

    write_file(root .. '/-proj-a/aaa-111.jsonl', {
      '{"type":"last-prompt","sessionId":"aaa-111"}',
      jsonl_line('oldest prompt', '/proj/a'),
    })
    write_file(root .. '/-proj-a/bbb-222.jsonl', {
      jsonl_line('middle prompt', '/proj/a'),
    })
    write_file(root .. '/-proj-b/ccc-333.jsonl', {
      jsonl_line('newest prompt', '/proj/b'),
    })

    -- garbage jsonl: id still resumable, title falls back
    write_file(root .. '/-proj-b/ddd-444.jsonl', { 'not json at all' })

    -- command-only jsonl: nothing to resume, excluded from the listing
    write_file(root .. '/-proj-b/fff-666.jsonl', {
      jsonl_line('<command-name>/clear</command-name> <command-message>clear</command-message>', '/proj/b'),
    })

    -- decoys that must be ignored
    vim.fn.mkdir(root .. '/-proj-a/aaa-111', 'p')
    write_file(root .. '/-proj-a/aaa-111/nested.jsonl', { jsonl_line('nested', '/x') })
    vim.fn.mkdir(root .. '/-proj-a/memory', 'p')
    write_file(root .. '/-proj-a/notes.txt', { 'plain text' })

    -- deterministic mtimes: oldest -> newest
    local base = os.time() - 100
    vim.uv.fs_utime(root .. '/-proj-a/aaa-111.jsonl', base, base)
    vim.uv.fs_utime(root .. '/-proj-a/bbb-222.jsonl', base + 10, base + 10)
    vim.uv.fs_utime(root .. '/-proj-b/ddd-444.jsonl', base + 20, base + 20)
    vim.uv.fs_utime(root .. '/-proj-b/ccc-333.jsonl', base + 30, base + 30)
  end)

  after_each(function()
    vim.fn.delete(root, 'rf')
  end)

  it('lists jsonl sessions sorted by mtime descending', function()
    local entries = history.list(root)
    assert.equals(4, #entries)
    assert.equals('ccc-333', entries[1].id)
    assert.equals('ddd-444', entries[2].id)
    assert.equals('bbb-222', entries[3].id)
    assert.equals('aaa-111', entries[4].id)
  end)

  it('extracts title, cwd, and mtime per entry', function()
    local entries = history.list(root)
    assert.equals('newest prompt', entries[1].title)
    assert.equals('/proj/b', entries[1].cwd)
    local stat = vim.uv.fs_stat(root .. '/-proj-b/ccc-333.jsonl')
    assert.equals(stat.mtime.sec, entries[1].mtime)
  end)

  it('extracts the latest session name from deep in the file', function()
    local lines = { jsonl_line('named session prompt', '/proj/b') }
    for _ = 1, 80 do
      table.insert(lines, '{"type":"assistant","message":{}}')
    end
    table.insert(lines, vim.json.encode({ type = 'agent-name', agentName = 'stale-name', sessionId = 'e' }))
    table.insert(lines, vim.json.encode({ type = 'agent-name', agentName = 'my-feature-work', sessionId = 'e' }))
    write_file(root .. '/-proj-b/eee-555.jsonl', lines)

    local entries = history.list(root)
    for _, e in ipairs(entries) do
      if e.id == 'eee-555' then
        assert.equals('my-feature-work', e.name)
        return
      end
    end
    error('eee-555 not found in entries')
  end)

  it('leaves name nil when the transcript has no agent-name', function()
    local entries = history.list(root)
    assert.equals('ccc-333', entries[1].id)
    assert.is_nil(entries[1].name)
  end)

  it('falls back to a placeholder title for unparseable files', function()
    local entries = history.list(root)
    assert.equals('(no prompt)', entries[2].title)
    assert.is_nil(entries[2].cwd)
  end)

  it('excludes command-only sessions from the listing', function()
    local entries = history.list(root)
    for _, e in ipairs(entries) do
      assert.not_equals('fff-666', e.id)
    end
  end)

  it('returns an empty list for a missing root', function()
    assert.same({}, history.list(root .. '/does-not-exist'))
  end)

  describe('delete', function()
    local function find(entries, id)
      for _, e in ipairs(entries) do
        if e.id == id then return e end
      end
    end

    it('removes the transcript and its checkpoint directory', function()
      local e = find(history.list(root), 'aaa-111')
      assert.is_true(history.delete(e))
      assert.equals(0, vim.fn.filereadable(root .. '/-proj-a/aaa-111.jsonl'))
      assert.equals(0, vim.fn.isdirectory(root .. '/-proj-a/aaa-111'))
      assert.is_nil(find(history.list(root), 'aaa-111'))
    end)

    it('leaves other sessions untouched', function()
      history.delete(find(history.list(root), 'aaa-111'))
      assert.is_not_nil(find(history.list(root), 'bbb-222'))
      assert.equals(1, vim.fn.isdirectory(root .. '/-proj-a/memory'))
    end)

    it('returns false when the transcript is already gone', function()
      local e = find(history.list(root), 'aaa-111')
      assert.is_true(history.delete(e))
      assert.is_false(history.delete(e))
    end)
  end)
end)

describe('history.filter_by_cwd', function()
  local history

  before_each(function()
    package.loaded['claude.history'] = nil
    history = require('claude.history')
  end)

  it('keeps only entries matching the cwd, preserving order', function()
    local entries = {
      { id = 'a', cwd = '/proj/a' },
      { id = 'b', cwd = '/proj/b' },
      { id = 'c', cwd = '/proj/a' },
      { id = 'd' },
    }
    local filtered = history.filter_by_cwd(entries, '/proj/a')
    assert.equals(2, #filtered)
    assert.equals('a', filtered[1].id)
    assert.equals('c', filtered[2].id)
  end)
end)
