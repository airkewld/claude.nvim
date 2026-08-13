-- ABOUTME: Creates and manages the floating window for Claude terminal output
-- ABOUTME: Handles show/hide lifecycle with centered positioning

local config = require('claude.config')

local M = {}

local function make_title(mode)
  local parts = { ' Claude' }
  if mode then
    table.insert(parts, ' - ' .. mode)
  end
  table.insert(parts, ' ')
  return table.concat(parts)
end

function M.open(bufnr)
  local cfg = config.get().window
  local width = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(vim.o.lines * cfg.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = cfg.border,
    title = make_title(),
    title_pos = 'center',
  })

  vim.api.nvim_set_option_value('spell', false, { win = winnr })

  return winnr
end

function M.set_title(winnr, mode)
  vim.api.nvim_win_set_config(winnr, {
    title = make_title(mode),
    title_pos = 'center',
  })
end

function M.resize(winnr)
  local cfg = config.get().window
  local width = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(vim.o.lines * cfg.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  vim.api.nvim_win_set_config(winnr, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
  })
end

return M
