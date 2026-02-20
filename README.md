# claude.nvim

Neovim plugin for running multiple Claude Code sessions in floating terminal windows with a Harpoon-style session picker.

## Features

- **Multiple named sessions** running simultaneously in hidden terminal buffers
- **Harpoon-style session menu** for browsing, selecting, creating, renaming, reordering, and deleting sessions
- **Idle detection** notifies you when a background session is waiting for input
- **Interactive/Review mode indicator** in the window title reflects whether you're typing or reading
- **Send context** from your current buffer or visual selection directly into a session
- **CLI argument passthrough** for flags like `--resume`, `--continue`, `--model`
- **Statusline integration** for lualine or any statusline plugin
- **Auto-cleanup** of exited sessions (opt-in)
- **Automatic CLAUDE.md rule enforcement** sends your project rules to Claude on session start
- **Esc to hide** — first Esc exits terminal mode, second Esc hides the floating window
- **Fully configurable** keymaps, window sizing, borders, and timeouts

## Requirements

- Neovim >= 0.9
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and in your `PATH`

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'airkewld/claude.nvim',
  config = function()
    require('claude').setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'airkewld/claude.nvim',
  config = function()
    require('claude').setup()
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'airkewld/claude.nvim'
```

Then in your `init.lua`:

```lua
require('claude').setup()
```

### [mini.deps](https://github.com/echasnovski/mini.deps)

```lua
MiniDeps.add({ source = 'airkewld/claude.nvim' })
require('claude').setup()
```

## Default Configuration

All values below are defaults. Pass a table to `setup()` to override any of them.

```lua
require('claude').setup({
  cli_args = { '--permission-mode', 'plan' },  -- default CLI args for every session
  enforce_claude_md = true,     -- send CLAUDE.md rules on session start
  claude_md_paths = {           -- paths to check for rule files
    { '~/.claude/CLAUDE.md', 'Global rules (~/.claude/CLAUDE.md)' },
    { 'CLAUDE.md', 'Local rules (CLAUDE.md)' },
    { '.claude/CLAUDE.md', 'Local rules (.claude/CLAUDE.md)' },
  },
  idle_timeout_ms = 3000,       -- ms before "waiting for input" notification
  auto_remove_exited = false,   -- automatically remove sessions after process exits
  window = {
    width = 0.8,                -- fraction of editor width
    height = 0.8,               -- fraction of editor height
    border = 'rounded',
  },
  menu = {
    width = 0.5,                -- fraction of editor width
    border = 'rounded',
  },
  keymaps = {
    toggle = '<leader>cl',      -- toggle active session window
    sessions = '<leader>cs',    -- open sessions menu
  },
})
```

Set any keymap to `false` to disable it.

## Keymaps

| Key | Mode | Action |
|-----|------|--------|
| `<leader>cl` | normal | Toggle active session (creates one if none exist) |
| `<leader>cs` | normal | Open sessions menu |
| `<Esc>` | terminal | Exit terminal mode (enter normal mode in the float) |
| `<Esc>` | normal (in float) | Hide the floating window |

## Commands

| Command | Action |
|---------|--------|
| `:Claude` | Toggle active session |
| `:Claude new [name] [args...]` | Create a new session with optional CLI args |
| `:Claude sessions` | Open the sessions menu |
| `:Claude next` | Switch to the next session |
| `:Claude prev` | Switch to the previous session |
| `:Claude send` | Send current file path to active session |
| `:'<,'>Claude send` | Send visual selection to active session |

### CLI Arguments

Arguments after the session name are passed directly to the `claude` CLI:

```vim
:Claude new my-session --resume
:Claude new quick-fix --model sonnet
```

## Sessions Menu

The sessions menu is a floating buffer listing all sessions with their status. Keymaps:

| Key | Action |
|-----|--------|
| `<CR>` | Select session under cursor |
| `1`-`9` | Jump to session by number |
| `n` | Create a new named session |
| `r` | Rename session under cursor |
| `d` | Delete session under cursor |
| `J` | Move session down |
| `K` | Move session up |
| `q` / `<Esc>` | Close menu |

## Window Title

The floating window title shows the session name and current interaction mode:

```
 Claude (my-session) - Interactive    ← typing in terminal mode
 Claude (my-session) - Review         ← reading in normal mode
```

## Statusline Integration

Add session info to your statusline. Returns `nil` when no sessions exist.

```lua
-- lualine example
require('lualine').setup({
  sections = {
    lualine_x = {
      { function() return require('claude.session').statusline() or '' end },
    },
  },
})
```

Output format:
- `Claude: my-session` — single session
- `Claude: my-session [2/3]` — multiple sessions, showing active index

## Idle Detection

When a background session produces output and then goes quiet for `idle_timeout_ms`, you'll get a notification:

```
Claude (my-session) is waiting for input
```

This only fires for sessions that aren't currently visible. Bringing the session into view resets the idle timer.

## Rule Enforcement

Claude doesn't always follow the rules in your CLAUDE.md files — it can lose track of them as conversations grow. This plugin addresses that by sending your rule files to the session as soon as it starts (on first idle), ensuring Claude always has them in context.

On first idle, the plugin checks for CLAUDE.md files at the configured paths and sends `@file` references into the session. Claude reads the referenced files and confirms before you start working.

Default paths checked:
- `~/.claude/CLAUDE.md` (global rules)
- `CLAUDE.md` (project root)
- `.claude/CLAUDE.md` (project config directory)

To disable: set `enforce_claude_md = false` in your setup. To customize which files are sent, override `claude_md_paths` — each entry is a `{ path, label }` pair.

## Auto-Cleanup

Set `auto_remove_exited = true` to automatically remove sessions 2 seconds after their Claude process exits. Disabled by default so you can review terminal output after exit.
