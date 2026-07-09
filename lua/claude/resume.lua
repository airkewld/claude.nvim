-- ABOUTME: Floating picker for resuming past Claude CLI sessions
-- ABOUTME: Tabs between current-project and all-project histories

local history = require('claude.history')
local config = require('claude.config')

local M = {}

local function shorten_path(path)
  if not path then return '' end
  local home = vim.env.HOME or ''
  if home ~= '' and path:sub(1, #home) == home then
    path = '~' .. path:sub(#home + 1)
  end
  return path
end

local function pad_right(str, width)
  local n = vim.fn.strdisplaywidth(str)
  if n >= width then return str end
  return str .. string.rep(' ', width - n)
end

local function pad_left(str, width)
  local n = #str
  if n >= width then return str end
  return string.rep(' ', width - n) .. str
end

local function build_rows(entries, now, width)
  local menu = require('claude.menu')
  local count = #entries
  local index_width = #tostring(count)

  local cwds, activities = {}, {}
  local cwd_width, activity_width = 0, 0
  for i, e in ipairs(entries) do
    cwds[i] = shorten_path(e.cwd)
    activities[i] = menu.format_activity(e.mtime, now)
    if #cwds[i] > cwd_width then cwd_width = #cwds[i] end
    if #activities[i] > activity_width then activity_width = #activities[i] end
  end

  local fixed = index_width + 2 + 2 + cwd_width + 2 + activity_width
  local max_title = math.max(width - fixed, 8)

  local titles = {}
  local title_width = 0
  for i, e in ipairs(entries) do
    local t = e.title or ''
    if vim.fn.strdisplaywidth(t) > max_title then
      t = vim.fn.strcharpart(t, 0, max_title - 1) .. '…'
    end
    titles[i] = t
    local w = vim.fn.strdisplaywidth(t)
    if w > title_width then title_width = w end
  end

  local lines = {}
  for i = 1, count do
    lines[i] = table.concat({
      pad_left(tostring(i), index_width),
      '  ',
      pad_right(titles[i], title_width),
      '  ',
      pad_right(cwds[i], cwd_width),
      '  ',
      activities[i],
    })
  end
  return lines
end

local function visible(entries, tab, cwd)
  if tab == 'project' then
    return history.filter_by_cwd(entries, cwd)
  end
  return entries
end

M._build_rows = build_rows
M._visible = visible

local function resume_entry(entry)
  local session = require('claude.session')

  for i, s in ipairs(session.list()) do
    if s.resume_id == entry.id and s.is_alive then
      session.set_active(i)
      require('claude').switch_to_active()
      return
    end
  end

  local s = session.create(nil, { '--resume', entry.id }, { cwd = entry.cwd })
  if not s then return end
  s.resume_id = entry.id
  require('claude').switch_to_active()
end

M._resume_entry = resume_entry

local picker_state = {
  bufnr = nil,
  winnr = nil,
  tab = 'project',
  entries = {},
  visible = {},
  cwd = nil,
}

local function is_open()
  return picker_state.winnr and vim.api.nvim_win_is_valid(picker_state.winnr)
end

local function title_for(tab)
  if tab == 'project' then
    return ' Resume  [This project]  All projects '
  end
  return ' Resume  This project  [All projects] '
end

function M.close()
  if is_open() then
    vim.api.nvim_win_hide(picker_state.winnr)
  end
  if picker_state.bufnr and vim.api.nvim_buf_is_valid(picker_state.bufnr) then
    vim.api.nvim_buf_delete(picker_state.bufnr, { force = true })
  end
  picker_state.bufnr = nil
  picker_state.winnr = nil
end

local function render()
  if not picker_state.bufnr then return end

  local lines
  if #picker_state.visible == 0 then
    if picker_state.tab == 'project' then
      lines = { '  (no sessions for this project — <Tab> for all)' }
    else
      lines = { '  (no past sessions)' }
    end
  else
    local width = vim.api.nvim_win_get_width(picker_state.winnr)
    lines = build_rows(picker_state.visible, os.time(), width)
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = picker_state.bufnr })
  vim.api.nvim_buf_set_lines(picker_state.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = picker_state.bufnr })
end

local function pick(index)
  local entry = picker_state.visible[index]
  if not entry then return end
  M.close()
  resume_entry(entry)
end

local function switch_tab()
  picker_state.tab = picker_state.tab == 'project' and 'all' or 'project'
  picker_state.visible = visible(picker_state.entries, picker_state.tab, picker_state.cwd)
  render()
  vim.api.nvim_win_set_config(picker_state.winnr, {
    title = title_for(picker_state.tab),
    title_pos = 'center',
  })
  vim.api.nvim_win_set_cursor(picker_state.winnr, { 1, 0 })
end

local function new_session()
  M.close()
  local session = require('claude.session')
  local s = session.create()
  if s then require('claude').switch_to_active() end
end

function M.open(entries)
  if is_open() then
    M.close()
    return
  end

  picker_state.entries = entries or history.list()
  picker_state.cwd = vim.fn.getcwd()
  picker_state.tab = 'project'
  picker_state.visible = visible(picker_state.entries, picker_state.tab, picker_state.cwd)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
  picker_state.bufnr = bufnr

  local cfg = config.get().menu
  local width = math.floor(vim.o.columns * cfg.width)
  local max_height = math.max(math.floor(vim.o.lines * 0.6), 3)
  local height = math.min(math.max(#picker_state.visible, 1) + 2, max_height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  picker_state.winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = cfg.border,
    title = title_for(picker_state.tab),
    title_pos = 'center',
    zindex = 60,
  })

  render()

  local opts = { buffer = bufnr, nowait = true }
  vim.keymap.set('n', '<CR>', function()
    pick(vim.api.nvim_win_get_cursor(picker_state.winnr)[1])
  end, opts)
  vim.keymap.set('n', '<Tab>', switch_tab, opts)
  vim.keymap.set('n', 'n', new_session, opts)
  for i = 1, 9 do
    vim.keymap.set('n', tostring(i), function() pick(i) end, opts)
  end
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)
end

return M
