#!/usr/bin/env bash
# Claude Code PreToolUse / PostToolUse hook.
# Reads hook payload JSON on stdin and posts a heartbeat with
# {file, project, language, editor, session_id} so parallel
# sessions remain distinct event streams in a shared bucket.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

payload="$(cat || true)"
if [ -z "$payload" ]; then exit 0; fi

session_id=$(printf '%s' "$payload" | jq -r '.session_id // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')
tool=$(printf '%s' "$payload" | jq -r '.tool_name // ""')
file=$(printf '%s' "$payload" | jq -r '
  .tool_input.file_path
  // .tool_input.notebook_path
  // .tool_input.path
  // ""
')

[ -z "$cwd" ] && cwd="$PWD"
[ -z "$file" ] && file="$cwd"

# Resolve relative paths against cwd so language detection sees real ext.
case "$file" in
  /*) ;;
  *) file="${cwd%/}/${file}" ;;
esac

project=$(aw_detect_project "$cwd")
language=$(aw_detect_language "$file")

aw_ensure_bucket || exit 0

# Note: `tool` is intentionally OMITTED from `data` so consecutive
# heartbeats on the same file within pulsetime merge into one event.
# session_id IS included so two parallel sessions editing the same
# file produce two distinct event streams.
data=$(jq -nc \
  --arg file "$file" \
  --arg project "$project" \
  --arg language "$language" \
  --arg editor "claude-code" \
  --arg session "$session_id" \
  '{file:$file, project:$project, language:$language, editor:$editor, session_id:$session}')

aw_heartbeat "$data" || exit 0
