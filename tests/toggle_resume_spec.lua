-- ABOUTME: Tests that toggling with no active session prompts for a name and starts one
-- ABOUTME: Drives the bare :Claude command with a stubbed session module and ui.input

describe('toggle with no active session', function()
  local created_name
  local create_called
  local active_session
  local input_response
  local orig_input

  before_each(function()
    created_name = nil
    create_called = false
    active_session = nil
    input_response = 'typed-name'

    for _, mod in ipairs({
      'claude', 'claude.config', 'claude.session',
      'claude.window', 'claude.resume', 'claude.terminal',
    }) do
      package.loaded[mod] = nil
    end

    package.loaded['claude.session'] = {
      get_active = function() return active_session end,
      get_winnr = function() return nil end,
      set_winnr = function() end,
      create = function(name)
        create_called = true
        created_name = name
        active_session = { name = name or 'fresh', bufnr = vim.api.nvim_create_buf(false, true), is_alive = true }
        return active_session
      end,
      find_by_bufnr = function() return nil, nil end,
      mark_input = function() end,
      is_idle = function() return false end,
      on_exit = function() end,
    }

    orig_input = vim.ui.input
    vim.ui.input = function(_, cb) cb(input_response) end

    require('claude').setup({})
  end)

  after_each(function()
    vim.ui.input = orig_input
  end)

  it('prompts for a name and creates a session with it', function()
    input_response = 'my-feature'
    vim.cmd('Claude')
    assert.is_true(create_called)
    assert.equals('my-feature', created_name)
  end)

  it('creates an unnamed session when the name is left blank', function()
    input_response = ''
    vim.cmd('Claude')
    assert.is_true(create_called)
    assert.is_nil(created_name)
  end)

  it('does not create a session when the prompt is cancelled', function()
    input_response = nil
    vim.cmd('Claude')
    assert.is_false(create_called)
  end)

  it('does not prompt or create when a session is already active', function()
    active_session = { name = 'live', bufnr = vim.api.nvim_create_buf(false, true), is_alive = true }
    vim.cmd('Claude')
    assert.is_false(create_called)
  end)

  it('the new-session keymap creates a session even when one is active', function()
    active_session = { name = 'live', bufnr = vim.api.nvim_create_buf(false, true), is_alive = true }
    input_response = 'another'

    local new_action
    for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
      if m.desc == 'New Claude session' and m.callback then new_action = m.callback end
    end
    assert.is_function(new_action)

    new_action()
    assert.is_true(create_called)
    assert.equals('another', created_name)
  end)
end)
