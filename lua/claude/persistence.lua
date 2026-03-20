-- ABOUTME: Persists session metadata to disk across Neovim restarts
-- ABOUTME: Handles UUID generation, CWD-scoped storage, and JSON read/write

local M = {}

local override_dir = nil

function M.generate_session_id()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (template:gsub('[xy]', function(c)
    local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
    return string.format('%x', v)
  end))
end

function M.encode_path(path)
  return path:gsub('/', '-')
end

function M._set_storage_dir(dir)
  override_dir = dir
end

function M.get_storage_dir()
  return override_dir or (vim.fn.stdpath('data') .. '/claude-nvim')
end

local function storage_file()
  local dir = M.get_storage_dir()
  local cwd = vim.fn.getcwd()
  return dir .. '/' .. M.encode_path(cwd) .. '.json'
end

function M.save(data)
  local dir = M.get_storage_dir()
  vim.fn.mkdir(dir, 'p')
  local path = storage_file()
  local json = vim.fn.json_encode(data)
  local f = io.open(path, 'w')
  if not f then
    vim.notify('claude.nvim: failed to write ' .. path, vim.log.levels.WARN)
    return
  end
  f:write(json)
  f:close()
end

function M.load()
  local path = storage_file()
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or type(data) ~= 'table' then
    vim.notify('claude.nvim: corrupt session file, starting fresh', vim.log.levels.WARN)
    return nil
  end
  return data
end

return M
