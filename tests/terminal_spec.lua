-- ABOUTME: Tests the terminal-mode keymaps set on Claude session buffers
-- ABOUTME: Covers Esc leaving terminal mode and the send-escape key reaching Claude

describe('terminal keymaps', function()
  local terminal

  before_each(function()
    package.loaded['claude.terminal'] = nil
    package.loaded['claude.config'] = nil
    require('claude.config').setup({})
    terminal = require('claude.terminal')
  end)

  local function find_map(bufnr, mode, lhs)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
      if m.lhs == lhs then return m end
    end
  end

  it('maps <Esc> in terminal mode to leave terminal mode', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    terminal._setup_keymaps(bufnr)
    assert.is_not_nil(find_map(bufnr, 't', '<Esc>'))
  end)

  it('maps the send_escape key to send a literal Esc to Claude', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.b[bufnr].claude_job_id = 99
    terminal._setup_keymaps(bufnr)

    local map = find_map(bufnr, 't', '<C-E>')
    assert.is_not_nil(map)
    assert.is_function(map.callback)

    local sent
    local orig = vim.fn.chansend
    vim.fn.chansend = function(job, data) sent = { job = job, data = data } end
    map.callback()
    vim.fn.chansend = orig

    assert.equals(99, sent.job)
    assert.equals('\27', sent.data)
  end)

  it('skips the send_escape mapping when disabled', function()
    require('claude.config').setup({ keymaps = { send_escape = false } })
    package.loaded['claude.terminal'] = nil
    terminal = require('claude.terminal')

    local bufnr = vim.api.nvim_create_buf(false, true)
    terminal._setup_keymaps(bufnr)
    assert.is_nil(find_map(bufnr, 't', '<C-G>'))
  end)
end)
