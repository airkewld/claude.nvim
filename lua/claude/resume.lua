-- ABOUTME: Floating picker for resuming past Claude CLI sessions
-- ABOUTME: Tabs between current-project and all-project histories

local history = require('claude.history')

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

return M
