-- ABOUTME: Manages terminal buffer lifecycle and Claude CLI process
-- ABOUTME: Handles spawning, exit detection, and input to running sessions

local M = {}

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

  -- Esc exits terminal mode; a second Esc in normal mode hides the float
  vim.api.nvim_buf_set_keymap(bufnr, 't', '<Esc>', [[<C-\><C-n>]], { noremap = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_exec_autocmds('User', { pattern = 'ClaudeHide' })
    end,
  })

  -- Y in visual mode yanks the selection with terminal wraps rejoined, so long
  -- commands paste as one line; copies to both the unnamed and system registers
  vim.api.nvim_buf_set_keymap(bufnr, 'x', 'Y', '', {
    noremap = true,
    callback = function()
      local srow, erow = vim.fn.line('v'), vim.fn.line('.')
      if srow > erow then srow, erow = erow, srow end
      local lines = vim.api.nvim_buf_get_lines(bufnr, srow - 1, erow, false)
      local text = M.smart_join(lines, vim.api.nvim_win_get_width(0))
      vim.fn.setreg('"', text)
      vim.fn.setreg('+', text)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    end,
  })

  return bufnr, vim.b[bufnr].claude_job_id
end

-- Rejoins terminal wrap-induced line breaks: a physical line that fills the
-- window width is a wrap continuation of the next line, so it joins with no
-- separator; a shorter line ends a logical line and keeps its newline.
function M.smart_join(lines, width)
  local parts = {}
  local cur = lines[1] or ''
  for i = 2, #lines do
    if vim.fn.strdisplaywidth(lines[i - 1]) >= width then
      cur = cur .. lines[i]
    else
      table.insert(parts, cur)
      cur = lines[i]
    end
  end
  table.insert(parts, cur)
  return table.concat(parts, '\n')
end

function M.send_input(job_id, text)
  vim.fn.chansend(job_id, text .. '\n')
end

return M
