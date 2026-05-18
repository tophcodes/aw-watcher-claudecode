#!/usr/bin/env bash
# Claude Code SessionStart hook.
# Reads hook payload JSON on stdin, ensures the AW bucket exists,
# and emits a marker heartbeat so dashboards see the session begin.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

payload="$(cat || true)"
if [ -z "$payload" ]; then payload='{}'; fi

session_id=$(printf '%s' "$payload" | jq -r '.session_id // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')
source=$(printf '%s' "$payload" | jq -r '.source // ""')

[ -z "$cwd" ] && cwd="$PWD"
project=$(aw_detect_project "$cwd")

aw_ensure_bucket || exit 0

data=$(jq -nc \
  --arg file "$cwd" \
  --arg project "$project" \
  --arg language "session" \
  --arg editor "claude-code" \
  --arg session "$session_id" \
  --arg source "$source" \
  '{file:$file, project:$project, language:$language, editor:$editor, session_id:$session, source:$source}')

aw_heartbeat "$data" || exit 0
