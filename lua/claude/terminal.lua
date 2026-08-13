-- ABOUTME: Manages terminal buffer lifecycle and Claude CLI process
-- ABOUTME: Handles spawning, exit detection, and input to running sessions

local config = require('claude.config')

local M = {}

function M._setup_keymaps(bufnr)
  -- Esc exits terminal mode; a second Esc in normal mode hides the float
  vim.api.nvim_buf_set_keymap(bufnr, 't', '<Esc>', [[<C-\><C-n>]], { noremap = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_exec_autocmds('User', { pattern = 'ClaudeHide' })
    end,
  })

  -- Sends a literal Esc to Claude (e.g. to step back in the --resume picker),
  -- since terminal-mode <Esc> above is claimed for leaving terminal mode.
  local send_escape = config.get().keymaps.send_escape
  if send_escape then
    vim.keymap.set('t', send_escape, function()
      vim.fn.chansend(vim.b[bufnr].claude_job_id, '\27')
    end, { buffer = bufnr })
  end
end

function M.create(args, opts)
  opts = opts or {}
  local cmd = 'claude'
  if args and #args > 0 then
    cmd = cmd .. ' ' .. table.concat(args, ' ')
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = bufnr })

  vim.api.nvim_buf_call(bufnr, function()
    local ei = vim.o.eventignore
    vim.o.eventignore = 'BufFilePost'
    local term_opts = {
      on_exit = function(_, exit_code)
        vim.api.nvim_exec_autocmds('User', { pattern = 'ClaudeExit', data = { bufnr = bufnr, exit_code = exit_code } })
      end,
    }
    if opts.cwd then
      term_opts.cwd = opts.cwd
    end
    local job_id = vim.fn.termopen(cmd, term_opts)
    vim.o.eventignore = ei
    vim.b[bufnr].claude_job_id = job_id
  end)

  M._setup_keymaps(bufnr)

  return bufnr, vim.b[bufnr].claude_job_id
end

function M.send_input(job_id, text)
  vim.fn.chansend(job_id, text .. '\n')
end

return M
