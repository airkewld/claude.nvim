-- ABOUTME: Holds default configuration and merges user overrides
-- ABOUTME: All modules read settings from config.get()

local M = {}

local defaults = {
  cli_args = { '--permission-mode', 'plan' },
  enforce_claude_md = true,
  claude_md_paths = {
    { '~/.claude/CLAUDE.md', 'Global rules (~/.claude/CLAUDE.md)' },
    { 'CLAUDE.md', 'Local rules (CLAUDE.md)' },
    { '.claude/CLAUDE.md', 'Local rules (.claude/CLAUDE.md)' },
  },
  idle_timeout_ms = 3000,
  auto_remove_exited = false,
  window = {
    width = 0.8,
    height = 0.8,
    border = 'rounded',
  },
  menu = {
    width = 0.5,
    border = 'rounded',
  },
  keymaps = {
    toggle = '<leader>cl',
    sessions = '<leader>cs',
  },
}

local config = nil

function M.setup(opts)
  config = vim.tbl_deep_extend('force', defaults, opts or {})
end

function M.get()
  if not config then
    M.setup({})
  end
  return config
end

return M
