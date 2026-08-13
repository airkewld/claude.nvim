-- ABOUTME: Session browser: lists past Claude CLI sessions with a transcript preview
-- ABOUTME: Toggle project scope with p, mark with <Space>/a, delete one or many with d

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

local function project_label(cwd)
  if not cwd or cwd == '' then return '(unknown)' end
  return vim.fn.fnamemodify(cwd, ':t')
end

local function build_rows(entries, marked, now, scope)
  local lines = {}
  for i, e in ipairs(entries) do
    local box = marked[i] and '[x]' or '[ ]'
    local prefix = scope == 'all' and (project_label(e.cwd) .. '/ ') or ''
    lines[i] = box .. ' ' .. prefix .. label_for(e) .. '  ' .. format_activity(e.mtime, now)
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

local function entries_for_scope(all, scope, cwd)
  if scope == 'all' then return all end
  return require('claude.history').filter_by_cwd(all, cwd)
end

local function target_entries(entries, marked, cursor_index)
  local marked_entries = collect_marked(entries, marked)
  if #marked_entries > 0 then return marked_entries end
  local e = entries[cursor_index]
  return e and { e } or {}
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
M._project_label = project_label
M._build_rows = build_rows
M._toggle = toggle
M._toggle_all = toggle_all
M._collect_marked = collect_marked
M._entries_for_scope = entries_for_scope
M._target_entries = target_entries
M._delete_entries = delete_entries

local picker = {
  list_buf = nil,
  list_win = nil,
  preview_buf = nil,
  preview_win = nil,
  entries = {},
  marked = {},
  scope = 'cwd',
  preview_cache = {},
}

local function is_open()
  return picker.list_win and vim.api.nvim_win_is_valid(picker.list_win)
end

local function title_for(scope)
  if scope == 'all' then return ' Claude Sessions — all projects ' end
  return ' Claude Sessions — this project '
end

function M.close()
  for _, win in ipairs({ picker.list_win, picker.preview_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_hide(win)
    end
  end
  for _, buf in ipairs({ picker.list_buf, picker.preview_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  picker.list_buf = nil
  picker.list_win = nil
  picker.preview_buf = nil
  picker.preview_win = nil
  picker.entries = {}
  picker.marked = {}
  picker.preview_cache = {}
end

local function set_lines(buf, lines)
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
end

local function render_list()
  if not picker.list_buf then return end
  local lines = build_rows(picker.entries, picker.marked, os.time(), picker.scope)
  if #lines == 0 then lines = { '(no sessions)' } end
  set_lines(picker.list_buf, lines)
end

local function current_entry()
  if not is_open() then return nil end
  local index = vim.api.nvim_win_get_cursor(picker.list_win)[1]
  return picker.entries[index]
end

local function render_preview()
  if not (picker.preview_buf and vim.api.nvim_buf_is_valid(picker.preview_buf)) then return end
  local entry = current_entry()
  local lines
  if entry then
    lines = picker.preview_cache[entry.id]
    if not lines then
      lines = require('claude.history').transcript(entry.path)
      picker.preview_cache[entry.id] = lines
    end
  end
  if not lines or #lines == 0 then lines = { '(no transcript)' } end
  set_lines(picker.preview_buf, lines)
  if picker.preview_win and vim.api.nvim_win_is_valid(picker.preview_win) then
    vim.api.nvim_win_set_cursor(picker.preview_win, { 1, 0 })
  end
end

local function scroll_preview(down)
  if not (picker.preview_win and vim.api.nvim_win_is_valid(picker.preview_win)) then return end
  vim.api.nvim_win_call(picker.preview_win, function()
    vim.cmd('normal! ' .. (down and '\4' or '\21'))
  end)
end

local function reload()
  local history = require('claude.history')
  picker.entries = entries_for_scope(history.list(), picker.scope, vim.fn.getcwd())
  picker.marked = {}
end

local function on_toggle()
  toggle(picker.marked, vim.api.nvim_win_get_cursor(picker.list_win)[1])
  render_list()
end

local function on_toggle_all()
  toggle_all(picker.marked, #picker.entries)
  render_list()
end

local function on_scope_toggle()
  picker.scope = picker.scope == 'cwd' and 'all' or 'cwd'
  reload()
  render_list()
  vim.api.nvim_win_set_config(picker.list_win, {
    title = title_for(picker.scope),
    title_pos = 'center',
  })
  if #picker.entries > 0 then
    vim.api.nvim_win_set_cursor(picker.list_win, { 1, 0 })
  end
  render_preview()
end

local function on_delete()
  local index = vim.api.nvim_win_get_cursor(picker.list_win)[1]
  local targets = target_entries(picker.entries, picker.marked, index)
  if #targets == 0 then
    vim.notify('Claude: nothing selected', vim.log.levels.INFO)
    return
  end
  delete_entries(targets)
  reload()
  if #picker.entries == 0 then
    M.close()
    return
  end
  render_list()
  vim.api.nvim_win_set_cursor(picker.list_win, { 1, 0 })
  render_preview()
end

function M.open()
  if is_open() then
    M.close()
    return
  end

  picker.scope = 'cwd'
  picker.preview_cache = {}
  reload()
  if #picker.entries == 0 then
    vim.notify('Claude: no past sessions for this project', vim.log.levels.INFO)
    return
  end

  picker.list_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = picker.list_buf })
  picker.preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = picker.preview_buf })
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = picker.preview_buf })

  local cfg = config.get().menu
  local total_w = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(vim.o.lines * (cfg.height or 0.8))
  local list_w = math.max(24, math.floor(total_w * 0.4))
  local preview_w = math.max(24, total_w - list_w - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - total_w) / 2)

  picker.preview_win = vim.api.nvim_open_win(picker.preview_buf, false, {
    relative = 'editor',
    width = preview_w,
    height = height,
    row = row,
    col = col + list_w + 3,
    style = 'minimal',
    border = cfg.border,
    title = ' Preview ',
    title_pos = 'center',
    zindex = 60,
  })
  vim.api.nvim_set_option_value('wrap', true, { win = picker.preview_win })
  vim.api.nvim_set_option_value('spell', false, { win = picker.preview_win })

  picker.list_win = vim.api.nvim_open_win(picker.list_buf, true, {
    relative = 'editor',
    width = list_w,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = cfg.border,
    title = title_for(picker.scope),
    title_pos = 'center',
    zindex = 61,
  })

  render_list()
  vim.api.nvim_win_set_cursor(picker.list_win, { 1, 0 })
  render_preview()

  local opts = { buffer = picker.list_buf, nowait = true }
  vim.keymap.set('n', '<Space>', on_toggle, opts)
  vim.keymap.set('n', 'a', on_toggle_all, opts)
  vim.keymap.set('n', 'p', on_scope_toggle, opts)
  vim.keymap.set('n', 'd', on_delete, opts)
  vim.keymap.set('n', '<CR>', on_delete, opts)
  vim.keymap.set('n', '<C-d>', function() scroll_preview(true) end, opts)
  vim.keymap.set('n', '<C-u>', function() scroll_preview(false) end, opts)
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = picker.list_buf,
    callback = render_preview,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    buffer = picker.list_buf,
    once = true,
    callback = vim.schedule_wrap(M.close),
  })
end

return M
