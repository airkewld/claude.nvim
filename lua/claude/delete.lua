-- ABOUTME: Multi-select floating picker for deleting past Claude CLI sessions
-- ABOUTME: Mark rows with <Space>/a, then delete the marked set behind one confirm

local config = require('claude.config')

local M = {}

local function label_for(e)
  return e.name or e.title or e.id
end

local function format_activity(ts, now)
  if not ts then return '' end
  local today = os.date('*t', now)
  local d = os.date('*t', ts)
  if d.year == today.year and d.yday == today.yday then
    return os.date('%H:%M', ts)
  end
  return os.date('%b %d', ts)
end

local function build_rows(entries, marked, now)
  local lines = {}
  for i, e in ipairs(entries) do
    local box = marked[i] and '[x]' or '[ ]'
    lines[i] = box .. ' ' .. label_for(e) .. '  ' .. format_activity(e.mtime, now)
  end
  return lines
end

local function toggle(marked, index)
  marked[index] = not marked[index] or nil
end

local function toggle_all(marked, count)
  local all_marked = count > 0
  for i = 1, count do
    if not marked[i] then
      all_marked = false
      break
    end
  end
  for i = 1, count do
    marked[i] = (not all_marked) or nil
  end
end

local function collect_marked(entries, marked)
  local out = {}
  for i, e in ipairs(entries) do
    if marked[i] then table.insert(out, e) end
  end
  return out
end

local function running_session_for(entry)
  local session = require('claude.session')
  for _, s in ipairs(session.list()) do
    if s.resume_id == entry.id and s.is_alive then
      return s
    end
  end
  return nil
end

local function delete_entries(entries)
  for _, e in ipairs(entries) do
    local running = running_session_for(e)
    if running then
      vim.notify('Claude: "' .. running.name .. '" is currently running — close it first', vim.log.levels.WARN)
      return 0
    end
  end

  local n = #entries
  local prompt = string.format('Delete %d session%s and their history?', n, n == 1 and '' or 's')
  if vim.fn.confirm(prompt, '&Yes\n&No', 2) ~= 1 then
    return 0
  end

  local deleted = 0
  local history = require('claude.history')
  for _, e in ipairs(entries) do
    if history.delete(e) then deleted = deleted + 1 end
  end

  local failed = n - deleted
  if failed > 0 then
    vim.notify(string.format('Claude: deleted %d, failed to delete %d', deleted, failed), vim.log.levels.ERROR)
  else
    vim.notify(string.format('Claude: deleted %d session%s', deleted, deleted == 1 and '' or 's'), vim.log.levels.INFO)
  end
  return deleted
end

M._label_for = label_for
M._build_rows = build_rows
M._toggle = toggle
M._toggle_all = toggle_all
M._collect_marked = collect_marked
M._delete_entries = delete_entries

local picker = {
  bufnr = nil,
  winnr = nil,
  entries = {},
  marked = {},
}

local function is_open()
  return picker.winnr and vim.api.nvim_win_is_valid(picker.winnr)
end

function M.close()
  if is_open() then
    vim.api.nvim_win_hide(picker.winnr)
  end
  if picker.bufnr and vim.api.nvim_buf_is_valid(picker.bufnr) then
    vim.api.nvim_buf_delete(picker.bufnr, { force = true })
  end
  picker.bufnr = nil
  picker.winnr = nil
  picker.entries = {}
  picker.marked = {}
end

local function render()
  if not picker.bufnr then return end
  local lines = build_rows(picker.entries, picker.marked, os.time())
  vim.api.nvim_set_option_value('modifiable', true, { buf = picker.bufnr })
  vim.api.nvim_buf_set_lines(picker.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = picker.bufnr })
end

local function cursor_line()
  return vim.api.nvim_win_get_cursor(picker.winnr)[1]
end

local function on_toggle()
  toggle(picker.marked, cursor_line())
  render()
end

local function on_toggle_all()
  toggle_all(picker.marked, #picker.entries)
  render()
end

local function reload()
  local history = require('claude.history')
  picker.entries = history.filter_by_cwd(history.list(), vim.fn.getcwd())
  picker.marked = {}
end

local function on_delete()
  local marked = collect_marked(picker.entries, picker.marked)
  if #marked == 0 then
    vim.notify('Claude: nothing selected', vim.log.levels.INFO)
    return
  end
  delete_entries(marked)
  reload()
  if #picker.entries == 0 then
    M.close()
    return
  end
  render()
  vim.api.nvim_win_set_cursor(picker.winnr, { 1, 0 })
end

function M.open()
  if is_open() then
    M.close()
    return
  end

  local history = require('claude.history')
  local entries = history.filter_by_cwd(history.list(), vim.fn.getcwd())
  if #entries == 0 then
    vim.notify('Claude: no past sessions for this project', vim.log.levels.INFO)
    return
  end

  picker.entries = entries
  picker.marked = {}

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
  picker.bufnr = bufnr

  local cfg = config.get().menu
  local width = math.floor(vim.o.columns * cfg.width)
  local height = #entries + 2
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  picker.winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = cfg.border,
    title = ' Delete Claude Sessions ',
    title_pos = 'center',
    zindex = 60,
  })

  render()
  vim.api.nvim_win_set_cursor(picker.winnr, { 1, 0 })

  local opts = { buffer = bufnr, nowait = true }
  vim.keymap.set('n', '<Space>', on_toggle, opts)
  vim.keymap.set('n', 'a', on_toggle_all, opts)
  vim.keymap.set('n', 'd', on_delete, opts)
  vim.keymap.set('n', '<CR>', on_delete, opts)
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)
end

return M
