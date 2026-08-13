-- ABOUTME: Tests the multi-select delete picker for removing past CLI sessions
-- ABOUTME: Drives the module's pure helpers with stubbed history, session, and confirm

describe('claude.delete', function()
  local delete
  local deleted
  local live_sessions
  local confirm_result
  local notified
  local orig_confirm, orig_notify

  local function entry(id, name, title)
    return { id = id, name = name, title = title, path = '/p/' .. id .. '.jsonl', cwd = '/proj', mtime = os.time() }
  end

  before_each(function()
    deleted = {}
    live_sessions = {}
    confirm_result = 1
    notified = nil

    for _, mod in ipairs({
      'claude.delete', 'claude.config', 'claude.session',
      'claude.menu', 'claude.history',
    }) do
      package.loaded[mod] = nil
    end

    package.loaded['claude.history'] = {
      list = function() return {} end,
      filter_by_cwd = function(entries) return entries end,
      delete = function(e) table.insert(deleted, e.id); return true end,
    }
    package.loaded['claude.session'] = {
      list = function() return live_sessions end,
    }
    package.loaded['claude.menu'] = {
      format_activity = function() return 'DATE' end,
    }

    orig_confirm = vim.fn.confirm
    orig_notify = vim.notify
    vim.fn.confirm = function() return confirm_result end
    vim.notify = function(msg) notified = msg end

    require('claude.config').setup({})
    delete = require('claude.delete')
  end)

  after_each(function()
    vim.fn.confirm = orig_confirm
    vim.notify = orig_notify
  end)

  describe('build_rows', function()
    it('renders an empty checkbox for unmarked rows and a filled one for marked rows', function()
      local entries = { entry('aaa', 'first'), entry('bbb', nil, 'second prompt') }
      local rows = delete._build_rows(entries, { [2] = true }, os.time())
      assert.equals(2, #rows)
      assert.truthy(rows[1]:match('^%[ %]'), 'unmarked row should start with [ ], got: ' .. rows[1])
      assert.truthy(rows[2]:match('^%[x%]'), 'marked row should start with [x], got: ' .. rows[2])
    end)

    it('includes the label and activity in each row', function()
      local entries = { entry('aaa', 'first') }
      local rows = delete._build_rows(entries, {}, os.time())
      assert.truthy(rows[1]:find('first', 1, true), 'expected label, got: ' .. rows[1])
      assert.truthy(rows[1]:find('DATE', 1, true), 'expected activity, got: ' .. rows[1])
    end)

    it('falls back to title then id for the label', function()
      local rows = delete._build_rows({ entry('bbb', nil, 'second prompt') }, {}, os.time())
      assert.truthy(rows[1]:find('second prompt', 1, true))
      rows = delete._build_rows({ entry('ccc', nil, nil) }, {}, os.time())
      assert.truthy(rows[1]:find('ccc', 1, true))
    end)
  end)

  describe('toggle helpers', function()
    it('toggles a single row on and off', function()
      local marked = {}
      delete._toggle(marked, 2)
      assert.is_true(marked[2])
      delete._toggle(marked, 2)
      assert.is_nil(marked[2])
    end)

    it('marks all rows when not all are marked', function()
      local marked = { [1] = true }
      delete._toggle_all(marked, 3)
      assert.is_true(marked[1])
      assert.is_true(marked[2])
      assert.is_true(marked[3])
    end)

    it('clears all rows when every row is already marked', function()
      local marked = { [1] = true, [2] = true }
      delete._toggle_all(marked, 2)
      assert.is_nil(marked[1])
      assert.is_nil(marked[2])
    end)

    it('collects the marked entries', function()
      local entries = { entry('aaa'), entry('bbb'), entry('ccc') }
      local collected = delete._collect_marked(entries, { [1] = true, [3] = true })
      assert.equals(2, #collected)
      assert.equals('aaa', collected[1].id)
      assert.equals('ccc', collected[2].id)
    end)
  end)

  describe('delete_entries', function()
    it('deletes every entry after a single confirmation', function()
      local n = delete._delete_entries({ entry('aaa'), entry('bbb') })
      assert.equals(2, n)
      assert.same({ 'aaa', 'bbb' }, deleted)
    end)

    it('does not delete when the user declines the confirmation', function()
      confirm_result = 2
      local n = delete._delete_entries({ entry('aaa') })
      assert.equals(0, n)
      assert.same({}, deleted)
    end)

    it('refuses the whole batch when any marked session is running', function()
      live_sessions = { { name = 'first', resume_id = 'aaa', is_alive = true } }
      local n = delete._delete_entries({ entry('aaa', 'first'), entry('bbb') })
      assert.equals(0, n)
      assert.same({}, deleted)
      assert.truthy(notified:match('currently running'))
    end)
  end)
end)
