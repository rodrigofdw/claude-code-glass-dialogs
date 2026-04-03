# Glass Dialogs for Claude Code

Native Windows acrylic glass overlay dialogs for Claude Code — replaces terminal prompts with beautiful, interactive popups you can respond to even when the terminal is minimized.

![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

## Features

- **Permission dialogs** — Allow / Always Allow / Deny with full tool details
- **Question dialogs** — Multi-choice option cards with radio/checkbox selection, keyboard navigation, "Other" free-text input
- **Response notifications** — Shows Claude's response text in a scrollable glass popup when a turn completes
- **Error/status alerts** — Tool failures, API errors, idle prompts
- **Acrylic blur-behind** — Native Windows 11 DWM compositor effects with rounded corners
- **Fade in/out transitions** — Smooth opacity animations
- **Environment badges** — Visual indicator showing WIN or WSL origin
- **Auto-timeout** — Dialogs auto-dismiss and fall back to the terminal prompt

## Requirements

- Windows 10 or 11
- [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases) (`pwsh` must be on your PATH)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [Node.js](https://nodejs.org/) (used for hook event parsing)

## Installation

### As a Claude Code plugin (recommended)

```bash
git clone https://github.com/rodrigofdw/claude-code-glass-dialogs.git ~/.claude/plugins/glass-dialogs
```

Then restart Claude Code. The plugin's hooks register automatically — no manual configuration needed.

To verify it's loaded, type `/hooks` in Claude Code and confirm the Glass Dialogs hooks appear.

### Manual installation (without plugin system)

If you prefer not to use the plugin system, you can clone anywhere and wire the hooks manually:

1. Clone the repo:
   ```bash
   git clone https://github.com/rodrigofdw/claude-code-glass-dialogs.git ~/Projects/claude-code-glass-dialogs
   ```

2. Add the following to your `~/.claude/settings.json` inside the top-level object:
   ```json
   "hooks": {
     "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/Projects/claude-code-glass-dialogs/scripts/notify.sh", "async": true, "timeout": 15 }] }],
     "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/Projects/claude-code-glass-dialogs/scripts/notify.sh", "async": true, "timeout": 15 }] }],
     "StopFailure": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/Projects/claude-code-glass-dialogs/scripts/notify.sh", "async": true, "timeout": 15 }] }],
     "PermissionRequest": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/Projects/claude-code-glass-dialogs/scripts/notify.sh", "timeout": 60 }] }],
     "PreToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "bash ~/Projects/claude-code-glass-dialogs/scripts/notify.sh", "timeout": 180 }] }]
   }
   ```
   Adjust the path if you cloned to a different location.

3. Restart Claude Code.

## WSL2 Support

The scripts auto-detect WSL2 and call `pwsh.exe` on the Windows host to render dialogs. Additional requirements for WSL2:

- PowerShell 7 installed on the Windows host (at the default `C:\Program Files\PowerShell\7\pwsh.exe`)
- Node.js available inside WSL2 (via nvm or system install)

For manual installation on WSL2, use the `/mnt/c/` path to the cloned repo in your WSL2 `~/.claude/settings.json`:
```json
"command": "bash /mnt/c/Users/YOURUSER/Projects/claude-code-glass-dialogs/scripts/notify.sh"
```

Dialogs display an orange **WSL** badge when triggered from WSL2 and a blue **WIN** badge from Windows.

## Keyboard Shortcuts

### Permission Dialog
| Key | Action |
|-----|--------|
| `Enter` / `Y` | Allow once |
| `A` / `S` | Always Allow (when available) |
| `Escape` / `N` / `D` | Deny |

### Question Dialog
| Key | Action |
|-----|--------|
| `Up` / `Down` | Navigate options |
| `Space` | Select/toggle option |
| `Tab` / `Shift+Tab` | Jump between questions |
| `Enter` | Submit |
| `Escape` | Skip (fall back to terminal) |

### Message Dialog
| Key | Action |
|-----|--------|
| `Enter` / `Space` / `Escape` | Dismiss |

## Uninstall

**Plugin install:** Delete `~/.claude/plugins/glass-dialogs/` and restart Claude Code.

**Manual install:** Remove the `"hooks"` block from your `~/.claude/settings.json` and delete the cloned repo.

## License

MIT
