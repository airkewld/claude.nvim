-- ABOUTME: Manages terminal buffer lifecycle and Claude CLI process
-- ABOUTME: Handles spawning, exit detection, and input to running sessions

local M = {}

function M.create(args)
  local cmd = 'claude'
  if args and #args > 0 then
    cmd = cmd .. ' ' .. table.concat(args, ' ')
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = bufnr })

  vim.api.nvim_buf_call(bufnr, function()
    local job_id = vim.fn.termopen(cmd, {
      on_exit = function()
        vim.api.nvim_exec_autocmds('User', { pattern = 'ClaudeExit', data = { bufnr = bufnr } })
      end,
    })
    vim.b[bufnr].claude_job_id = job_id
  end)

  -- Esc exits terminal mode so normal-mode keymaps (like leader+cl) work
  vim.api.nvim_buf_set_keymap(bufnr, 't', '<Esc>', [[<C-\><C-n>]], { noremap = true })

  return bufnr, vim.b[bufnr].claude_job_id
end

function M.send_input(job_id, text)
  vim.fn.chansend(job_id, text .. '\n')
end

return M
