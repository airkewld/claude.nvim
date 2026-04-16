-- ABOUTME: Tests for menu formatting helpers
-- ABOUTME: Covers activity column format and row layout alignment

describe('menu', function()
  local menu

  before_each(function()
    package.loaded['claude.menu'] = nil
    package.loaded['claude.session'] = nil
    package.loaded['claude.config'] = nil

    package.loaded['claude.session'] = {
      list = function() return {} end,
      active_index = function() return 0 end,
      is_dormant = function(s) return s.bufnr == nil end,
    }

    require('claude.config').setup({})
    menu = require('claude.menu')
  end)

  describe('format_activity', function()
    it('returns empty string for nil timestamp', function()
      assert.equals('', menu._format_activity(nil, os.time()))
    end)

    it('returns HH:MM for timestamps on the same calendar day', function()
      local now = os.time()
      local out = menu._format_activity(now - 60, now)
      assert.truthy(out:match('^%d%d:%d%d$'), 'expected HH:MM, got: ' .. out)
    end)

    it('returns "Mon DD" for timestamps on a prior calendar day', function()
      local now = os.time()
      local two_days_ago = now - 2 * 86400
      local out = menu._format_activity(two_days_ago, now)
      assert.truthy(out:match('^%a%a%a %d+$'), 'expected "Mon DD", got: ' .. out)
    end)
  end)

  describe('build_rows', function()
    local function fake(name, cwd)
      return { name = name, cwd = cwd, bufnr = 1, is_alive = true, last_activity_at = os.time() }
    end

    it('aligns the cwd column across rows with mixed-length names', function()
      local sessions = {
        fake('short', vim.env.HOME .. '/a'),
        fake('a-much-longer-session-name', vim.env.HOME .. '/b'),
        fake('mid-length', vim.env.HOME .. '/c'),
      }
      local lines = menu._build_rows(sessions, 1, os.time())
      assert.equals(#sessions, #lines)

      local first_offset = lines[1]:find('~', 1, true)
      assert.is_number(first_offset)
      for i = 2, #lines do
        assert.equals(first_offset, lines[i]:find('~', 1, true),
          'row ' .. i .. ' cwd offset mismatch: ' .. lines[i])
      end
    end)

    it('aligns the status column across rows with mixed-length names', function()
      local sessions = {
        fake('short', vim.env.HOME .. '/a'),
        fake('a-much-longer-session-name', vim.env.HOME .. '/bb'),
        fake('mid-length', vim.env.HOME .. '/ccc'),
      }
      local lines = menu._build_rows(sessions, 1, os.time())
      local first_offset = lines[1]:find('%[', 1)
      assert.is_number(first_offset)
      for i = 2, #lines do
        assert.equals(first_offset, lines[i]:find('%[', 1),
          'row ' .. i .. ' status offset mismatch: ' .. lines[i])
      end
    end)

    it('right-aligns the index column when the list has 10+ entries', function()
      local sessions = {}
      for i = 1, 12 do
        table.insert(sessions, fake('s' .. i, vim.env.HOME .. '/p'))
      end
      local lines = menu._build_rows(sessions, 1, os.time())
      -- Marker is a single char ('>' or ' '), then a space, then the index field.
      -- For 12 entries, index field is width 2; single-digit idx should be padded left with a space.
      local row9 = lines[9]
      local row10 = lines[10]
      assert.truthy(row9:match('^. +9 '), 'row 9 expected " 9" padding, got: ' .. row9)
      assert.truthy(row10:match('^. +10 '), 'row 10 expected "10" no padding, got: ' .. row10)

      -- Name column should start at the same offset in both.
      local p9 = row9:find('s9', 1, true)
      local p10 = row10:find('s10', 1, true)
      assert.equals(p9, p10)
    end)

    it('includes the activity column on the right', function()
      local ts = os.time()
      local sessions = { fake('only', vim.env.HOME .. '/a') }
      sessions[1].last_activity_at = ts
      local lines = menu._build_rows(sessions, 1, ts)
      local expected = menu._format_activity(ts, ts)
      assert.truthy(lines[1]:sub(- #expected) == expected,
        'expected row to end with "' .. expected .. '", got: ' .. lines[1])
    end)
  end)
end)
