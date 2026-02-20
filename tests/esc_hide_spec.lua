-- ABOUTME: Tests that Esc in normal mode hides the Claude floating window
-- ABOUTME: Verifies the ClaudeHide autocmd closes and untracks the window

describe('esc hides floating window', function()
  before_each(function()
    package.loaded['claude'] = nil
    package.loaded['claude.config'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.window'] = nil
    package.loaded['claude.terminal'] = nil
    package.loaded['claude.menu'] = nil
  end)

  it('ClaudeHide autocmd closes the tracked window', function()
    local claude = require('claude')
    claude.setup({})

    local session = require('claude.session')

    local bufnr = vim.api.nvim_create_buf(false, true)
    local winnr = vim.api.nvim_open_win(bufnr, true, {
      relative = 'editor',
      width = 40,
      height = 10,
      row = 1,
      col = 1,
    })
    session.set_winnr(winnr)

    assert.is_true(vim.api.nvim_win_is_valid(winnr))

    vim.api.nvim_exec_autocmds('User', { pattern = 'ClaudeHide' })

    assert.is_false(vim.api.nvim_win_is_valid(winnr))
    assert.is_nil(session.get_winnr())
  end)
end)
