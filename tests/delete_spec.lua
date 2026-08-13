-- ABOUTME: Tests the :Claude delete command for removing past CLI sessions
-- ABOUTME: Drives the command with stubbed history, vim.ui.select, and confirm

describe(':Claude delete', function()
  local listed
  local deleted
  local selected
  local select_called
  local notified
  local live_sessions
  local confirm_result
  local orig_select, orig_confirm, orig_notify

  before_each(function()
    listed = {
      { id = 'aaa', name = 'first', title = 't1', cwd = '/proj', mtime = os.time() },
      { id = 'bbb', name = nil, title = 'second prompt', cwd = '/proj', mtime = os.time() },
    }
    deleted = nil
    selected = 1
    select_called = false
    notified = nil
    live_sessions = {}
    confirm_result = 1

    for _, mod in ipairs({
      'claude', 'claude.config', 'claude.session', 'claude.menu',
      'claude.window', 'claude.history', 'claude.terminal', 'claude.resume',
    }) do
      package.loaded[mod] = nil
    end

    package.loaded['claude.history'] = {
      list = function() return listed end,
      filter_by_cwd = function(entries) return entries end,
      delete = function(entry) deleted = entry; return true end,
    }
    package.loaded['claude.session'] = {
      get_active = function() return nil end,
      get_winnr = function() return nil end,
      set_winnr = function() end,
      list = function() return live_sessions end,
      find_by_bufnr = function() return nil, nil end,
      mark_input = function() end,
      is_idle = function() return false end,
      on_exit = function() end,
    }
    package.loaded['claude.menu'] = {
      open = function() end,
      format_activity = function() return 'DATE' end,
    }

    orig_select = vim.ui.select
    orig_confirm = vim.fn.confirm
    orig_notify = vim.notify
    vim.ui.select = function(items, _, cb)
      select_called = true
      cb(items[selected])
    end
    vim.fn.confirm = function() return confirm_result end
    vim.notify = function(msg) notified = msg end

    require('claude').setup({})
  end)

  after_each(function()
    vim.ui.select = orig_select
    vim.fn.confirm = orig_confirm
    vim.notify = orig_notify
  end)

  it('deletes the chosen session after confirmation', function()
    selected = 2
    vim.cmd('Claude delete')
    assert.is_not_nil(deleted)
    assert.equals('bbb', deleted.id)
  end)

  it('does not delete when the user declines the confirmation', function()
    confirm_result = 2
    vim.cmd('Claude delete')
    assert.is_nil(deleted)
  end)

  it('refuses to delete a session that is currently running', function()
    selected = 1
    live_sessions = { { name = 'first', resume_id = 'aaa', is_alive = true } }
    vim.cmd('Claude delete')
    assert.is_nil(deleted)
    assert.truthy(notified:match('currently running'))
  end)

  it('notifies and skips the picker when the project has no sessions', function()
    listed = {}
    vim.cmd('Claude delete')
    assert.is_false(select_called)
    assert.truthy(notified:match('no past sessions'))
  end)
end)
