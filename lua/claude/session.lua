-- ABOUTME: Manages multiple named Claude sessions with idle detection
-- ABOUTME: Provides create/remove/cycle operations and shared window state

local terminal = require('claude.terminal')
local config = require('claude.config')
local rules = require('claude.rules')
local persistence = require('claude.persistence')

local M = {}

local state = {
  sessions = {},
  active = 0,
  winnr = nil,
  counter = 0,
  deleted_ids = {},
}

local function stop_idle_timer(session)
  if session.idle_timer then
    session.idle_timer:stop()
    session.idle_timer:close()
    session.idle_timer = nil
  end
end

local function session_visible(session)
  return state.winnr
    and vim.api.nvim_win_is_valid(state.winnr)
    and state.sessions[state.active] == session
end

function M._handle_idle(session)
  if not session.is_alive then return end

  if not session.init_prompt_sent and config.get().enforce_claude_md then
    local prompt = rules.build_init_prompt()
    if prompt then
      session.init_prompt_sent = true
      terminal.send_input(session.job_id, prompt)
      return
    end
  end

  if not session_visible(session) and not session.notified_idle then
    session.notified_idle = true
    vim.notify('Claude (' .. session.name .. ') is waiting for input', vim.log.levels.INFO)
  end
end

local function watch_output(session)
  vim.api.nvim_buf_attach(session.bufnr, false, {
    on_lines = function()
      if not session.is_alive then return true end
      session.notified_idle = false
      stop_idle_timer(session)
      session.idle_timer = vim.uv.new_timer()
      session.idle_timer:start(config.get().idle_timeout_ms, 0, vim.schedule_wrap(function()
        M._handle_idle(session)
      end))
    end,
  })
end

function M.create(name, args)
  if vim.fn.executable('claude') ~= 1 then
    vim.notify('claude: not found in PATH', vim.log.levels.ERROR)
    return nil
  end

  if not name then
    state.counter = state.counter + 1
    name = 'session-' .. state.counter
  end

  for _, s in ipairs(state.sessions) do
    if s.name == name then
      vim.notify('Claude session "' .. name .. '" already exists', vim.log.levels.ERROR)
      return nil
    end
  end

  local cli_args = config.get().cli_args
  if cli_args and #cli_args > 0 then
    local merged = { unpack(cli_args) }
    if args then
      for _, a in ipairs(args) do
        table.insert(merged, a)
      end
    end
    args = merged
  end

  local session_id = persistence.generate_session_id()
  if not args then args = {} end
  table.insert(args, '--session-id')
  table.insert(args, session_id)

  local bufnr, job_id = terminal.create(args)
  local session = {
    name = name,
    session_id = session_id,
    cwd = vim.fn.getcwd(),
    bufnr = bufnr,
    job_id = job_id,
    is_alive = true,
    idle_timer = nil,
    notified_idle = false,
    init_prompt_sent = false,
    last_input_at = vim.uv.now(),
  }

  table.insert(state.sessions, session)
  state.active = #state.sessions
  watch_output(session)
  M.save_state()
  return session
end

function M.remove(index)
  local session = state.sessions[index]
  if not session then return end

  state.deleted_ids[session.session_id] = true

  stop_idle_timer(session)
  if session.bufnr and vim.api.nvim_buf_is_valid(session.bufnr) then
    vim.api.nvim_buf_delete(session.bufnr, { force = true })
  end

  table.remove(state.sessions, index)

  if #state.sessions == 0 then
    state.active = 0
  elseif state.active > #state.sessions then
    state.active = #state.sessions
  elseif state.active > index then
    state.active = state.active - 1
  end

  M.save_state()
end

function M.get_active()
  return state.sessions[state.active]
end

function M.set_active(index)
  if index >= 1 and index <= #state.sessions then
    state.active = index
  end
end

function M.next()
  if #state.sessions <= 1 then return end
  state.active = (state.active % #state.sessions) + 1
end

function M.prev()
  if #state.sessions <= 1 then return end
  state.active = ((state.active - 2) % #state.sessions) + 1
end

function M.list()
  return state.sessions
end

function M.count()
  return #state.sessions
end

function M.active_index()
  return state.active
end

function M.swap(i, j)
  if i < 1 or i > #state.sessions or j < 1 or j > #state.sessions then return false end
  state.sessions[i], state.sessions[j] = state.sessions[j], state.sessions[i]
  if state.active == i then
    state.active = j
  elseif state.active == j then
    state.active = i
  end
  M.save_state()
  return true
end

function M.rename(index, new_name)
  local s = state.sessions[index]
  if not s then return false end
  for i, other in ipairs(state.sessions) do
    if i ~= index and other.name == new_name then
      vim.notify('Claude session "' .. new_name .. '" already exists', vim.log.levels.ERROR)
      return false
    end
  end
  s.name = new_name
  M.save_state()
  return true
end

function M.mark_input(session)
  session.last_input_at = vim.uv.now()
end

function M.is_idle(session, now, threshold)
  if not threshold or threshold <= 0 then return false end
  if not session.last_input_at then return false end
  return (now - session.last_input_at) >= threshold
end

function M.find_by_bufnr(bufnr)
  for i, s in ipairs(state.sessions) do
    if s.bufnr == bufnr then
      return i, s
    end
  end
  return nil, nil
end

function M.on_exit(bufnr, exit_code)
  local index, session = M.find_by_bufnr(bufnr)
  if not session then return end

  local resume_failed = session.resuming and exit_code ~= 0
  session.resuming = nil

  session.is_alive = false
  stop_idle_timer(session)

  if resume_failed then
    vim.notify('Session "' .. session.name .. '" could not be resumed (not found in CLI)', vim.log.levels.WARN)
  elseif not session_visible(session) then
    vim.notify('Claude (' .. session.name .. ') session ended', vim.log.levels.INFO)
  end

  if config.get().auto_remove_exited then
    vim.defer_fn(function()
      local i = M.find_by_bufnr(bufnr)
      if i then M.remove(i) end
    end, 2000)
  end
end

function M.statusline()
  if #state.sessions == 0 then return nil end
  local s = state.sessions[state.active]
  if not s then return nil end
  if #state.sessions == 1 then
    return 'Claude: ' .. s.name
  end
  return string.format('Claude: %s [%d/%d]', s.name, state.active, #state.sessions)
end

function M.is_dormant(s)
  return s.bufnr == nil
end

function M.save_state()
  local local_ids = {}
  local local_sessions = {}
  for _, s in ipairs(state.sessions) do
    local entry = { name = s.name, session_id = s.session_id, cwd = s.cwd }
    table.insert(local_sessions, entry)
    local_ids[s.session_id] = true
  end

  -- Merge sessions from disk that this instance doesn't know about
  local disk = persistence.load()
  if disk and disk.sessions then
    for _, s in ipairs(disk.sessions) do
      if not local_ids[s.session_id] and not state.deleted_ids[s.session_id] then
        table.insert(local_sessions, { name = s.name, session_id = s.session_id, cwd = s.cwd })
      end
    end
  end

  persistence.save({
    sessions = local_sessions,
    active = state.active,
    counter = state.counter,
  })
end

function M.refresh_state()
  local data = persistence.load()
  if not data or not data.sessions then return end

  local running = {}
  for _, s in ipairs(state.sessions) do
    if s.bufnr then
      running[s.session_id] = s
    end
  end

  local current_active_id = nil
  if state.active >= 1 and state.active <= #state.sessions then
    current_active_id = state.sessions[state.active].session_id
  end

  local new_sessions = {}
  local new_active = data.active or 1

  for _, saved in ipairs(data.sessions) do
    local local_session = running[saved.session_id]
    if local_session then
      local_session.name = saved.name
      local_session.cwd = saved.cwd
      table.insert(new_sessions, local_session)
    else
      table.insert(new_sessions, {
        name = saved.name,
        session_id = saved.session_id,
        cwd = saved.cwd,
        bufnr = nil,
        job_id = nil,
        is_alive = false,
        idle_timer = nil,
        notified_idle = false,
        init_prompt_sent = true,
      })
    end
    if saved.session_id == current_active_id then
      new_active = #new_sessions
    end
  end

  -- Keep locally running sessions that were deleted on disk
  for _, s in pairs(running) do
    local found = false
    for _, ns in ipairs(new_sessions) do
      if ns.session_id == s.session_id then
        found = true
        break
      end
    end
    if not found then
      table.insert(new_sessions, s)
    end
  end

  state.sessions = new_sessions
  if #new_sessions == 0 then
    state.active = 0
  else
    state.active = math.min(new_active, #new_sessions)
  end
  state.counter = data.counter or #new_sessions
end

function M.load_state()
  local data = persistence.load()
  if not data or not data.sessions or #data.sessions == 0 then return end

  for _, saved in ipairs(data.sessions) do
    table.insert(state.sessions, {
      name = saved.name,
      session_id = saved.session_id,
      cwd = saved.cwd,
      bufnr = nil,
      job_id = nil,
      is_alive = false,
      idle_timer = nil,
      notified_idle = false,
      init_prompt_sent = true,
    })
  end

  state.active = data.active or 1
  state.counter = data.counter or #state.sessions
end

function M.resume(index)
  local s = state.sessions[index]
  if not s or not M.is_dormant(s) then return end

  if vim.fn.executable('claude') ~= 1 then
    vim.notify('claude: not found in PATH', vim.log.levels.ERROR)
    return
  end

  local cli_args = config.get().cli_args
  local args = {}
  if cli_args and #cli_args > 0 then
    for _, a in ipairs(cli_args) do
      table.insert(args, a)
    end
  end
  table.insert(args, '--resume')
  table.insert(args, s.session_id)

  local bufnr, job_id = terminal.create(args, { cwd = s.cwd })
  s.bufnr = bufnr
  s.job_id = job_id
  s.is_alive = true
  s.resuming = true
  s.init_prompt_sent = true
  s.last_input_at = vim.uv.now()
  watch_output(s)
  M.save_state()
end

function M.get_winnr()
  return state.winnr
end

function M.set_winnr(winnr)
  state.winnr = winnr
end

return M
