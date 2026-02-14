-- ABOUTME: Harpoon-style floating menu for browsing and switching Claude sessions
-- ABOUTME: Supports select, delete, and keyboard navigation

local session = require('claude.session')
local config = require('claude.config')

local M = {}

local menu_state = {
  bufnr = nil,
  winnr = nil,
}

local function is_open()
  return menu_state.winnr and vim.api.nvim_win_is_valid(menu_state.winnr)
end

function M.close()
  if is_open() then
    vim.api.nvim_win_hide(menu_state.winnr)
  end
  if menu_state.bufnr and vim.api.nvim_buf_is_valid(menu_state.bufnr) then
    vim.api.nvim_buf_delete(menu_state.bufnr, { force = true })
  end
  menu_state.bufnr = nil
  menu_state.winnr = nil
end

function M.render()
  if not menu_state.bufnr then return end

  local sessions = session.list()
  local active = session.active_index()
  local lines = {}

  if #sessions == 0 then
    table.insert(lines, '  (no sessions)')
  else
    for i, s in ipairs(sessions) do
      local marker = i == active and '>' or ' '
      local status = s.is_alive and '[running]' or '[exited]'
      table.insert(lines, string.format('%s %d  %-20s %s', marker, i, s.name, status))
    end
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = menu_state.bufnr })
  vim.api.nvim_buf_set_lines(menu_state.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = menu_state.bufnr })
end

function M.select()
  local cursor = vim.api.nvim_win_get_cursor(menu_state.winnr)
  local line = cursor[1]
  if line >= 1 and line <= session.count() then
    session.set_active(line)
    M.close()
    require('claude').switch_to_active()
  end
end

function M.delete()
  local cursor = vim.api.nvim_win_get_cursor(menu_state.winnr)
  local line = cursor[1]
  if line < 1 or line > session.count() then return end

  session.remove(line)

  if session.count() == 0 then
    M.close()
    require('claude').hide_window()
    return
  end

  M.render()

  local new_line = math.min(line, session.count())
  vim.api.nvim_win_set_cursor(menu_state.winnr, { new_line, 0 })
end

function M.move_up()
  local cursor = vim.api.nvim_win_get_cursor(menu_state.winnr)
  local line = cursor[1]
  if line <= 1 then return end
  if session.swap(line, line - 1) then
    M.render()
    vim.api.nvim_win_set_cursor(menu_state.winnr, { line - 1, 0 })
  end
end

function M.move_down()
  local cursor = vim.api.nvim_win_get_cursor(menu_state.winnr)
  local line = cursor[1]
  if line >= session.count() then return end
  if session.swap(line, line + 1) then
    M.render()
    vim.api.nvim_win_set_cursor(menu_state.winnr, { line + 1, 0 })
  end
end

function M.rename()
  local cursor = vim.api.nvim_win_get_cursor(menu_state.winnr)
  local line = cursor[1]
  if line < 1 or line > session.count() then return end

  local s = session.list()[line]
  vim.ui.input({ prompt = 'Rename "' .. s.name .. '": ', default = s.name }, function(new_name)
    if not new_name or new_name == '' or new_name == s.name then return end
    if session.rename(line, new_name) then
      M.render()
      local winnr = session.get_winnr()
      if winnr and vim.api.nvim_win_is_valid(winnr) and session.active_index() == line then
        require('claude.window').set_title(winnr, new_name)
      end
    end
  end)
end

function M.new_session()
  M.close()
  vim.ui.input({ prompt = 'Session name: ' }, function(name)
    if not name or name == '' then return end
    local s = session.create(name)
    if s then require('claude').switch_to_active() end
  end)
end

function M.open()
  if is_open() then
    M.close()
    return
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
  menu_state.bufnr = bufnr

  local cfg = config.get().menu
  local line_count = math.max(session.count(), 1)
  local width = math.floor(vim.o.columns * cfg.width)
  local height = line_count + 2
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  menu_state.winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = cfg.border,
    title = ' Claude Sessions ',
    title_pos = 'center',
    zindex = 60,
  })

  M.render()

  local active = session.active_index()
  if active >= 1 then
    vim.api.nvim_win_set_cursor(menu_state.winnr, { active, 0 })
  end

  local opts = { buffer = bufnr, nowait = true }
  vim.keymap.set('n', '<CR>', M.select, opts)
  vim.keymap.set('n', 'd', M.delete, opts)
  vim.keymap.set('n', 'n', M.new_session, opts)
  vim.keymap.set('n', 'r', M.rename, opts)
  vim.keymap.set('n', 'K', M.move_up, opts)
  vim.keymap.set('n', 'J', M.move_down, opts)
  for i = 1, math.min(session.count(), 9) do
    vim.keymap.set('n', tostring(i), function()
      session.set_active(i)
      M.close()
      require('claude').switch_to_active()
    end, opts)
  end
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)
end

return M
