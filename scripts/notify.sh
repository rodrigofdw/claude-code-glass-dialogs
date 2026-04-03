#!/bin/bash
# Glass Dialogs for Claude Code — hook event dispatcher
# Auto-detects Windows (Git Bash) vs WSL2 environment

INPUT=$(cat)

case "$INPUT" in
  *'"PermissionRequest"'*|*'"Notification"'*|*'"Stop"'*|*'"StopFailure"'*|*'"PostToolUseFailure"'*|*'"AskUserQuestion"'*) ;;
  *) exit 0 ;;
esac

# ── Environment detection ───────────────────────────────────────────
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ -n "$WSL_DISTRO_NAME" ]; then
  SCRIPTS_WIN=$(wslpath -w "$PLUGIN_ROOT/scripts")
  ICON=$(wslpath -w "$PLUGIN_ROOT/assets/claude-code.png")
  PWSH="/mnt/c/Program Files/PowerShell/7/pwsh.exe"
  SOURCE="WSL2"
  to_winpath() { wslpath -w "$1"; }
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
  NODE_PATH=$(ls -d "$NVM_DIR/versions/node"/*/bin 2>/dev/null | tail -1)
  [ -n "$NODE_PATH" ] && export PATH="$NODE_PATH:$PATH"
else
  SCRIPTS_WIN=$(cd "$PLUGIN_ROOT/scripts" && pwd -W 2>/dev/null || pwd)
  SCRIPTS_WIN=$(echo "$SCRIPTS_WIN" | sed 's|/|\\|g')
  ICON="${SCRIPTS_WIN}\\..\\assets\\claude-code.png"
  PWSH="pwsh"
  SOURCE="Windows"
  to_winpath() { cygpath -w "$1"; }
fi

# ── Load config ─────────────────────────────────────────────────────
CONFIG_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.config/glass-dialogs}"
CONFIG_FILE="$CONFIG_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$CONFIG_DIR"
  cp "$PLUGIN_ROOT/config.defaults.json" "$CONFIG_FILE" 2>/dev/null
fi

# Parse config with node (fast — reuses the same node we need for event parsing anyway)
if [ -f "$CONFIG_FILE" ]; then
  eval "$(cat "$CONFIG_FILE" | node -e "
    const c = JSON.parse(require('fs').readFileSync(0,'utf8'));
    console.log('CFG_PERM_ENABLED=' + (c.permissions?.enabled !== false ? '1' : '0'));
    console.log('CFG_PERM_TIMEOUT=' + (c.permissions?.timeoutSeconds || 45));
    console.log('CFG_QUEST_ENABLED=' + (c.questions?.enabled !== false ? '1' : '0'));
    console.log('CFG_QUEST_TIMEOUT=' + (c.questions?.timeoutSeconds || 120));
    console.log('CFG_MSG_ENABLED=' + (c.messages?.enabled !== false ? '1' : '0'));
    console.log('CFG_MSG_TIMEOUT=' + (c.messages?.timeoutSeconds || 30));
    console.log('CFG_SOUND=' + (c.sound !== false ? '1' : '0'));
  " 2>/dev/null)" || true
fi

# Apply defaults if config parsing failed
: "${CFG_PERM_ENABLED:=1}" "${CFG_PERM_TIMEOUT:=45}"
: "${CFG_QUEST_ENABLED:=1}" "${CFG_QUEST_TIMEOUT:=120}"
: "${CFG_MSG_ENABLED:=1}" "${CFG_MSG_TIMEOUT:=30}"
: "${CFG_SOUND:=1}"

# ── Parse hook event ────────────────────────────────────────────────
PARSED=$(echo "$INPUT" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
  console.log('HOOK_EVENT=' + JSON.stringify(d.hook_event_name || ''));
  console.log('TOOL_NAME=' + JSON.stringify(d.tool_name || ''));
  console.log('TRANSCRIPT=' + JSON.stringify(d.transcript_path || ''));
" 2>/dev/null) || true
eval "$PARSED"

# ── Permission Request ──────────────────────────────────────────────
if [ "$HOOK_EVENT" = "PermissionRequest" ]; then
  if [ "$CFG_PERM_ENABLED" = "0" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}'
    exit 0
  fi

  TMPFILE=$(mktemp --suffix=.json)
  echo "$INPUT" > "$TMPFILE"

  RAW=$("$PWSH" -NoProfile -File "${SCRIPTS_WIN}\\permission-dialog.ps1" \
    -JsonFile "$(to_winpath "$TMPFILE")" \
    -IconPath "$ICON" -Source "$SOURCE" \
    -TimeoutSeconds "$CFG_PERM_TIMEOUT" 2>/dev/null)
  rm -f "$TMPFILE"

  RAW=${RAW:-ask}
  RAW=$(echo "$RAW" | tr -d '\r\n')

  if [[ "$RAW" == always::* ]]; then
    PERMS_JSON="${RAW#always::}"
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\",\"updatedPermissions\":[${PERMS_JSON}]}}}"
  else
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"${RAW}\"}}}"
  fi
  exit 0
fi

# ── AskUserQuestion ─────────────────────────────────────────────────
if [ "$HOOK_EVENT" = "PreToolUse" ] && [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  [ "$CFG_QUEST_ENABLED" = "0" ] && exit 0

  TMPFILE=$(mktemp --suffix=.json)
  echo "$INPUT" > "$TMPFILE"

  ANSWER=$("$PWSH" -NoProfile -File "${SCRIPTS_WIN}\\question-dialog.ps1" \
    -JsonFile "$(to_winpath "$TMPFILE")" \
    -IconPath "$ICON" -Source "$SOURCE" \
    -TimeoutSeconds "$CFG_QUEST_TIMEOUT" 2>/dev/null)
  rm -f "$TMPFILE"

  if [ -n "$ANSWER" ] && [ "$ANSWER" != "::SKIP::" ]; then
    echo "User answered via notification dialog: $ANSWER" >&2
    exit 2
  fi
  exit 0
fi

# ── Informational events ───────────────────────────────────────────
[ "$CFG_MSG_ENABLED" = "0" ] && exit 0

TITLE="" MESSAGE="" TIMEOUT="$CFG_MSG_TIMEOUT" SOUND_FLAG=""
[ "$CFG_SOUND" = "1" ] && SOUND_BASE="-PlaySound" || SOUND_BASE=""

case "$HOOK_EVENT" in
  Notification)
    TITLE="Claude Code — Input Required"
    MESSAGE="Claude is waiting for your input."
    TIMEOUT=60; SOUND_FLAG="$SOUND_BASE"
    ;;
  Stop)
    TITLE="Claude Code — Response Complete"
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      MESSAGE=$(tail -10 "$TRANSCRIPT" | node -e "
        const lines = require('fs').readFileSync(0,'utf8').trim().split('\n');
        for (let i = lines.length - 1; i >= 0; i--) {
          try {
            const e = JSON.parse(lines[i]);
            if (e.type === 'assistant' && e.message && e.message.content) {
              const parts = e.message.content.filter(c => c.type === 'text').map(c => c.text);
              if (parts.length > 0) {
                let t = parts.join('\n');
                if (t.length > 3000) t = t.substring(0, 2997) + '...';
                process.stdout.write(t); process.exit(0);
              }
            }
          } catch(ex) {}
        }
        process.stdout.write('Response complete.');
      " 2>/dev/null) || MESSAGE="Response complete."
    else
      MESSAGE="Response complete."
    fi
    ;;
  StopFailure)
    TITLE="Claude Code — Error"
    MESSAGE="The turn ended due to an error."
    TIMEOUT=45; SOUND_FLAG="$SOUND_BASE"
    ;;
  PostToolUseFailure)
    TITLE="Claude Code — Tool Error"
    MESSAGE="Tool failed: ${TOOL_NAME:-unknown}"
    SOUND_FLAG="$SOUND_BASE"
    ;;
  *) exit 0 ;;
esac

if [ -n "$MESSAGE" ]; then
  MSG_TMP=$(mktemp --suffix=.txt)
  echo "$MESSAGE" > "$MSG_TMP"
  MSG_WIN=$(to_winpath "$MSG_TMP")

  (
    "$PWSH" -NoProfile -c "
      \$msg = Get-Content -Path \"$MSG_WIN\" -Raw -Encoding UTF8
      Remove-Item -Path \"$MSG_WIN\" -Force -ErrorAction SilentlyContinue
      & \"${SCRIPTS_WIN}\\message-dialog.ps1\" -Title \"$TITLE\" -Message \$msg -IconPath \"$ICON\" -TimeoutSeconds $TIMEOUT -Source \"$SOURCE\" $SOUND_FLAG
    " 2>/dev/null
    rm -f "$MSG_TMP" 2>/dev/null
  ) &
fi

exit 0
