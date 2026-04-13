-- ABOUTME: Persists session metadata to disk across Neovim restarts
-- ABOUTME: Handles UUID generation, global storage, migration, and JSON read/write

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

function M.decode_path(encoded)
  if not encoded or encoded == '' then return nil end
  if encoded:sub(1, 1) ~= '-' then return nil end

  local segments = {}
  for seg in encoded:sub(2):gmatch('[^-]+') do
    table.insert(segments, seg)
  end
  if #segments == 0 then return nil end

  local path = ''
  local i = 1
  while i <= #segments do
    local candidate = path .. '/' .. segments[i]
    if i == #segments then
      if vim.fn.isdirectory(candidate) == 1 then
        return candidate
      end
      return nil
    elseif vim.fn.isdirectory(candidate) == 1 then
      path = candidate
      i = i + 1
    else
      local combined = segments[i]
      local found = false
      for j = i + 1, #segments do
        combined = combined .. '-' .. segments[j]
        local try = path .. '/' .. combined
        if j == #segments then
          if vim.fn.isdirectory(try) == 1 then
            return try
          end
          return nil
        elseif vim.fn.isdirectory(try) == 1 then
          path = try
          i = j + 1
          found = true
          break
        end
      end
      if not found then return nil end
    end
  end
  return nil
end

function M._set_storage_dir(dir)
  override_dir = dir
end

function M.get_storage_dir()
  return override_dir or (vim.fn.stdpath('data') .. '/claude-nvim')
end

local function storage_file()
  local dir = M.get_storage_dir()
  return dir .. '/sessions.json'
end

local function load_json(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or type(data) ~= 'table' then return nil end
  return data
end

local function migrate()
  local dir = M.get_storage_dir()
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return nil end

  local merged_sessions = {}
  local max_counter = 0

  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if typ == 'file' and name:match('%.json$') and name ~= 'sessions.json' then
      local filepath = dir .. '/' .. name
      local data = load_json(filepath)
      if data and data.sessions then
        local encoded = name:gsub('%.json$', '')
        local cwd = M.decode_path(encoded)
        for _, s in ipairs(data.sessions) do
          table.insert(merged_sessions, {
            name = s.name,
            session_id = s.session_id,
            cwd = cwd,
          })
        end
        if data.counter and data.counter > max_counter then
          max_counter = data.counter
        end
      end
    end
  end

  if #merged_sessions == 0 then return nil end

  local result = {
    sessions = merged_sessions,
    active = 1,
    counter = max_counter,
  }
  M.save(result)
  return result
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
  local data = load_json(path)
  if data then return data end

  return migrate()
end

return M
