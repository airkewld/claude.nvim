-- ABOUTME: Tests for CLAUDE.md rule reading and prompt building
-- ABOUTME: Validates file reading, prompt formatting, and missing file handling

describe('rules', function()
  local rules
  local tmpdir

  before_each(function()
    package.loaded['claude.rules'] = nil
    rules = require('claude.rules')
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
  end)

  after_each(function()
    vim.fn.delete(tmpdir, 'rf')
  end)

  local function write_file(path, content)
    local f = io.open(path, 'w')
    f:write(content)
    f:close()
  end

  it('returns nil when no files exist', function()
    local result = rules.build_init_prompt({
      { tmpdir .. '/nonexistent.md', 'Test' },
    })
    assert.is_nil(result)
  end)

  it('includes @ reference for a single file', function()
    local path = tmpdir .. '/CLAUDE.md'
    write_file(path, 'Rule 1: Be nice')

    local result = rules.build_init_prompt({
      { path, 'Test rules' },
    })
    assert.is_not_nil(result)
    assert.truthy(result:find('@' .. path, 1, true))
    assert.falsy(result:find('Rule 1: Be nice', 1, true))
  end)

  it('includes @ references for multiple files', function()
    local global = tmpdir .. '/global.md'
    local local_md = tmpdir .. '/local.md'
    write_file(global, 'Global rule')
    write_file(local_md, 'Local rule')

    local result = rules.build_init_prompt({
      { global, 'Global' },
      { local_md, 'Local' },
    })
    assert.is_not_nil(result)
    assert.truthy(result:find('@' .. global, 1, true))
    assert.truthy(result:find('@' .. local_md, 1, true))
    assert.falsy(result:find('Global rule', 1, true))
    assert.falsy(result:find('Local rule', 1, true))
  end)

  it('skips files that do not exist', function()
    local path = tmpdir .. '/CLAUDE.md'
    write_file(path, 'Exists')

    local result = rules.build_init_prompt({
      { tmpdir .. '/nonexistent.md', 'Missing' },
      { path, 'Present' },
    })
    assert.is_not_nil(result)
    assert.truthy(result:find('@' .. path, 1, true))
    assert.falsy(result:find('nonexistent.md', 1, true))
  end)

  it('skips empty files', function()
    local path = tmpdir .. '/empty.md'
    write_file(path, '')

    local result = rules.build_init_prompt({
      { path, 'Empty' },
    })
    assert.is_nil(result)
  end)

  it('uses default CLAUDE.md paths when none provided', function()
    local result = rules.build_init_prompt()
    -- Should not error, returns nil or string depending on whether files exist
    assert.is_true(result == nil or type(result) == 'string')
  end)
end)
