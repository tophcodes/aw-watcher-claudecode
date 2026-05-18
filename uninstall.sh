#!/usr/bin/env bash
# Remove aw-watcher-claudecode hook entries from a Claude Code
# settings.json. Backs up the file before writing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="${SCRIPT_DIR}/hooks"

TARGET="${HOME}/.claude/settings.json"

usage() {
  cat <<EOF
Usage: $0 [--target PATH]

Removes hook entries referencing this checkout's hooks/ scripts.
Default target: ~/.claude/settings.json
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) shift; TARGET="$1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

if [ ! -f "$TARGET" ]; then
  echo "nothing to do: $TARGET does not exist"
  exit 0
fi

BACKUP="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "backup written: $BACKUP"

jq \
  --arg ss "${HOOK_DIR}/session-start.sh" \
  --arg te "${HOOK_DIR}/tool-event.sh" \
  '
  def strip(key; needle):
    if .hooks[key] then
      .hooks[key] = ([
        .hooks[key][]
        | .hooks = ([(.hooks // [])[]
            | select((.command // "") | contains(needle) | not)])
        | select(.hooks | length > 0)
      ])
      | if .hooks[key] == [] then del(.hooks[key]) else . end
    else . end;

  strip("SessionStart"; $ss)
  | strip("PreToolUse"; $te)
  | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$BACKUP" > "$TARGET"

echo "removed aw-watcher-claudecode entries from: $TARGET"
