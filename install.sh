#!/usr/bin/env bash
# Merge aw-watcher-claudecode hook bindings into a Claude Code
# settings.json file using jq. Idempotent — running twice is a no-op.
# Backups the existing file before writing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="${SCRIPT_DIR}/hooks"

SCOPE="global"
PROJECT_DIR=""
TARGET=""
SERVER=""
PULSETIME=""
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 [options]

Merges aw-watcher-claudecode hooks into a Claude Code settings.json.

Scope (pick one):
  --global             ~/.claude/settings.json                  (default)
  --project [DIR]      <DIR>/.claude/settings.json              (DIR defaults to \$PWD)
  --local [DIR]        <DIR>/.claude/settings.local.json        (gitignored override)
  --target PATH        write to PATH explicitly

Env baked into hook commands (optional):
  --server URL         AW_SERVER for the hook scripts
                       (default: unset → http://127.0.0.1:5600)
  --pulsetime SECS     AW_PULSETIME for the hook scripts
                       (default: unset → 120)

Other:
  --dry-run            print merged JSON, write nothing
  -h, --help           this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --global) SCOPE=global; shift ;;
    --project)
      SCOPE=project; shift
      if [ $# -gt 0 ] && [[ "$1" != --* ]]; then PROJECT_DIR="$1"; shift; fi
      ;;
    --local)
      SCOPE=local; shift
      if [ $# -gt 0 ] && [[ "$1" != --* ]]; then PROJECT_DIR="$1"; shift; fi
      ;;
    --target) shift; SCOPE=explicit; TARGET="$1"; shift ;;
    --server) shift; SERVER="$1"; shift ;;
    --pulsetime) shift; PULSETIME="$1"; shift ;;
    --dry-run|--print) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$SCOPE" in
  global)   TARGET="${HOME}/.claude/settings.json" ;;
  project)  TARGET="${PROJECT_DIR:-$PWD}/.claude/settings.json" ;;
  local)    TARGET="${PROJECT_DIR:-$PWD}/.claude/settings.local.json" ;;
  explicit) : ;;
esac

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

build_cmd() {
  local script="$1"
  local env=""
  [ -n "$SERVER" ] && env+="AW_SERVER=${SERVER} "
  [ -n "$PULSETIME" ] && env+="AW_PULSETIME=${PULSETIME} "
  if [ -n "$env" ]; then
    printf 'env %s%s' "$env" "$script"
  else
    printf '%s' "$script"
  fi
}

SS_CMD=$(build_cmd "${HOOK_DIR}/session-start.sh")
TE_CMD=$(build_cmd "${HOOK_DIR}/tool-event.sh")

FRAGMENT=$(jq -nc \
  --arg ss "$SS_CMD" \
  --arg te "$TE_CMD" \
  '{
    hooks: {
      SessionStart: [
        { hooks: [{ type: "command", command: $ss }] }
      ],
      PreToolUse: [
        { matcher: "Edit|MultiEdit|Write|Read|NotebookEdit|Glob|Grep|Bash",
          hooks: [{ type: "command", command: $te }] }
      ]
    }
  }')

EXISTING="{}"
if [ -f "$TARGET" ]; then
  EXISTING="$(cat "$TARGET")"
  if ! printf '%s' "$EXISTING" | jq . >/dev/null 2>&1; then
    echo "error: $TARGET is not valid JSON" >&2
    exit 1
  fi
fi

# Merge logic:
#   - existing.hooks.SessionStart += fragment.hooks.SessionStart  (skip if our script path already referenced)
#   - existing.hooks.PreToolUse   += fragment.hooks.PreToolUse    (same)
MERGED=$(jq -n \
  --argjson existing "$EXISTING" \
  --argjson frag "$FRAGMENT" \
  --arg ss_path "${HOOK_DIR}/session-start.sh" \
  --arg te_path "${HOOK_DIR}/tool-event.sh" \
  '
  def has_path(needle):
    [.[]?.hooks[]?.command // ""] | any(contains(needle));

  def append_unique(key; needle):
    if (.hooks[key] // []) | has_path(needle) then .
    else .hooks[key] = ((.hooks[key] // []) + ($frag.hooks[key])) end;

  $existing
  | (.hooks //= {})
  | append_unique("SessionStart"; $ss_path)
  | append_unique("PreToolUse"; $te_path)
  ')

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$MERGED" | jq .
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"

if [ -f "$TARGET" ]; then
  BACKUP="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$TARGET" "$BACKUP"
  echo "backup written: $BACKUP"
fi

printf '%s\n' "$MERGED" | jq . > "$TARGET"
echo "installed into: $TARGET"
echo
echo "next:"
echo "  - start a new Claude Code session to load hooks"
echo "  - ensure aw-server is reachable at \${AW_SERVER:-http://127.0.0.1:5600}"
echo "  - remove with: ${SCRIPT_DIR}/uninstall.sh --target $TARGET"
