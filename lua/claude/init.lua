-- ABOUTME: Public API for the Claude Code Neovim plugin
-- ABOUTME: Wires keymaps, commands, and autocmds to session and menu modules

local config = require('claude.config')
local window = require('claude.window')
local session = require('claude.session')
local menu = require('claude.menu')

local M = {}

local function win_visible()
  local winnr = session.get_winnr()
  return winnr and vim.api.nvim_win_is_valid(winnr)
end

local function hide()
  local winnr = session.get_winnr()
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_hide(winnr)
    session.set_winnr(nil)
  end
end

local function mode_label()
  local mode = vim.api.nvim_get_mode().mode
  if mode == 't' or mode == 'i' then
    return 'Interactive'
  end
  return 'Review'
end

local function update_title()
  local winnr = session.get_winnr()
  local s = session.get_active()
  if winnr and vim.api.nvim_win_is_valid(winnr) and s then
    window.set_title(winnr, s.name, mode_label())
  end
end

local function show(s)
  local winnr = window.open(s.bufnr, s.name)
  session.set_winnr(winnr)
  vim.cmd('startinsert')
  update_title()
end

function M.switch_to_active()
  local s = session.get_active()
  if not s then return end

  local winnr = session.get_winnr()
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_set_buf(winnr, s.bufnr)
    vim.cmd('startinsert')
    update_title()
  else
    show(s)
  end
end

function M.hide_window()
  hide()
end

local function toggle()
  local s = session.get_active()

  if not s or not vim.api.nvim_buf_is_valid(s.bufnr) then
    session.create()
    s = session.get_active()
    if not s then return end
    show(s)
    return
  end

  if win_visible() then
    hide()
    return
  end

  show(s)
end

local function send_to_session(opts)
  local s = session.get_active()
  if not s or not s.is_alive then
    vim.notify('Claude: no active running session', vim.log.levels.ERROR)
    return
  end

  local terminal = require('claude.terminal')

  if opts.range > 0 then
    local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
    local filepath = vim.fn.expand('%:.')
    local text = string.format(
      'From %s (lines %d-%d):\n```\n%s\n```',
      filepath, opts.line1, opts.line2, table.concat(lines, '\n')
    )
    terminal.send_input(s.job_id, text)
  else
    local filepath = vim.fn.expand('%:p')
    terminal.send_input(s.job_id, '/add-file ' .. filepath)
  end

  if not win_visible() then
    show(s)
  end
end

local subcommands = {
  new = function(args)
    local name = args[1]
    local cli_args = { unpack(args, 2) }
    local s = session.create(name, #cli_args > 0 and cli_args or nil)
    if s then M.switch_to_active() end
  end,
  sessions = function()
    menu.open()
  end,
  next = function()
    session.next()
    if win_visible() then M.switch_to_active() end
  end,
  prev = function()
    session.prev()
    if win_visible() then M.switch_to_active() end
  end,
}

function M.setup(opts)
  config.setup(opts)
  local keys = config.get().keymaps

  local function map(key, fn, desc)
    if key then vim.keymap.set('n', key, fn, { desc = desc }) end
  end
  map(keys.toggle, toggle, 'Toggle Claude Code')
  map(keys.sessions, menu.open, 'Claude sessions menu')

  vim.api.nvim_create_user_command('Claude', function(cmd)
    local args = cmd.fargs
    local sub = args[1]
    if not sub then
      toggle()
      return
    end
    if sub == 'send' then
      send_to_session(cmd)
      return
    end
    local handler = subcommands[sub]
    if handler then
      handler({ unpack(args, 2) })
    else
      vim.notify('Claude: unknown subcommand "' .. sub .. '"', vim.log.levels.ERROR)
    end
  end, {
    nargs = '*',
    range = true,
    complete = function(_, line)
      local parts = vim.split(line, '%s+')
      if #parts <= 2 then
        local prefix = parts[2] or ''
        local all_cmds = { 'send' }
        for name, _ in pairs(subcommands) do
          table.insert(all_cmds, name)
        end
        local matches = {}
        for _, name in ipairs(all_cmds) do
          if name:find(prefix, 1, true) == 1 then
            table.insert(matches, name)
          end
        end
        table.sort(matches)
        return matches
      end
      return {}
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    pattern = 'ClaudeExit',
    callback = function(ev)
      local bufnr = ev.data and ev.data.bufnr
      if bufnr then
        session.on_exit(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd('ModeChanged', {
    callback = function()
      if win_visible() then
        local cur_win = vim.api.nvim_get_current_win()
        if cur_win == session.get_winnr() then
          update_title()
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    callback = function()
      if win_visible() then
        window.resize(session.get_winnr())
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(ev)
      local winnr = session.get_winnr()
      if winnr and tostring(winnr) == ev.match then
        session.set_winnr(nil)
      end
    end,
  })
end

return M
