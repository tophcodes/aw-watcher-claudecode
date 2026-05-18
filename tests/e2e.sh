#!/usr/bin/env bash
# End-to-end test: spin up an isolated aw-server, fire simulated
# Claude Code hook payloads at the hook scripts, then curl the
# aw-server back to assert events were recorded correctly.
#
# Covers:
#   1. Bucket creation
#   2. Single-session events (file, project, language fields)
#   3. Parallel sessions stay distinct (session_id in event data)
#   4. Heartbeat merging within a session (same file, repeated)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_DIR="${REPO_ROOT}/hooks"
RUN_DIR="${REPO_ROOT}/tests/_run"
PORT="${AW_TEST_PORT:-5699}"
SERVER="http://127.0.0.1:${PORT}"
HOST="$(hostname -s 2>/dev/null || hostname)"
BUCKET="aw-watcher-claudecode_${HOST}"

export AW_SERVER="$SERVER"
export AW_PULSETIME=120

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR/config" "$RUN_DIR/cache" "$RUN_DIR/data"

cleanup() {
  if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log() { printf '\033[1;34m[e2e]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
pass() { printf '\033[1;32m[PASS]\033[0m %s\n' "$*"; }

# --- start isolated aw-server -------------------------------------------------
log "starting aw-server on :${PORT} (data dir: ${RUN_DIR})"
XDG_CONFIG_HOME="$RUN_DIR/config" \
XDG_CACHE_HOME="$RUN_DIR/cache" \
XDG_DATA_HOME="$RUN_DIR/data" \
  aw-server \
    --host 127.0.0.1 \
    --port "$PORT" \
    --testing \
    >"$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!

# Wait until /api/0/info responds (up to ~10s).
for i in $(seq 1 50); do
  if curl -fsS "${SERVER}/api/0/info" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
if ! curl -fsS "${SERVER}/api/0/info" >/dev/null; then
  cat "$RUN_DIR/server.log" >&2
  fail "aw-server did not come up on ${SERVER}"
fi
pass "aw-server is up"

# --- helpers ------------------------------------------------------------------
fire_session_start() {
  local sess="$1" cwd="$2"
  jq -nc \
    --arg sid "$sess" --arg cwd "$cwd" \
    '{session_id:$sid, cwd:$cwd, hook_event_name:"SessionStart", source:"startup"}' \
    | bash "${HOOK_DIR}/session-start.sh"
}

fire_tool_event() {
  local sess="$1" cwd="$2" tool="$3" file="$4"
  jq -nc \
    --arg sid "$sess" --arg cwd "$cwd" --arg tool "$tool" --arg f "$file" \
    '{session_id:$sid, cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$tool, tool_input:{file_path:$f}}' \
    | bash "${HOOK_DIR}/tool-event.sh"
}

get_events() {
  curl -fsS "${SERVER}/api/0/buckets/${BUCKET}/events?limit=500"
}

# --- 1. Bucket creation -------------------------------------------------------
log "test 1: SessionStart creates bucket"
fire_session_start "sess-alpha" "$PWD"
curl -fsS "${SERVER}/api/0/buckets/${BUCKET}" >/dev/null \
  || fail "bucket ${BUCKET} was not created"
pass "bucket exists"

# --- 2. Single-session events -------------------------------------------------
log "test 2: tool events record file/project/language"
fire_tool_event "sess-alpha" "$PWD" "Edit" "${PWD}/hooks/lib.sh"
fire_tool_event "sess-alpha" "$PWD" "Read" "${PWD}/README.md"
fire_tool_event "sess-alpha" "/tmp" "Write" "/tmp/scratch.py"

evs=$(get_events)
count=$(jq 'length' <<<"$evs")
[ "$count" -ge 3 ] || fail "expected >=3 events, got ${count}"

langs=$(jq -r '[.[].data.language] | unique | join(",")' <<<"$evs")
log "languages seen: ${langs}"
for needle in shell markdown python; do
  jq -e --arg l "$needle" '[.[].data.language] | index($l)' <<<"$evs" >/dev/null \
    || fail "language '${needle}' not detected"
done
pass "language detection working (${langs})"

# Project field populated from cwd walk-up.
jq -e '[.[].data.project] | map(select(. != "" and . != null)) | length > 0' <<<"$evs" >/dev/null \
  || fail "project field empty on all events"
pass "project field populated"

# --- 3. Parallel sessions stay distinct ---------------------------------------
log "test 3: parallel sessions kept distinct via session_id"
# Two sessions edit the SAME file. Without session_id in data they'd merge
# into one heartbeat-extended event. With it, two separate streams exist.
fire_session_start "sess-beta" "$PWD"
fire_tool_event "sess-alpha" "$PWD" "Edit" "${PWD}/shared.rs"
fire_tool_event "sess-beta"  "$PWD" "Edit" "${PWD}/shared.rs"
fire_tool_event "sess-alpha" "$PWD" "Edit" "${PWD}/shared.rs"
fire_tool_event "sess-beta"  "$PWD" "Edit" "${PWD}/shared.rs"

evs=$(get_events)
shared_alpha=$(jq '[.[] | select(.data.file | endswith("shared.rs")) | select(.data.session_id=="sess-alpha")] | length' <<<"$evs")
shared_beta=$(jq  '[.[] | select(.data.file | endswith("shared.rs")) | select(.data.session_id=="sess-beta")]  | length' <<<"$evs")
log "shared.rs events: alpha=${shared_alpha} beta=${shared_beta}"
[ "$shared_alpha" -ge 1 ] || fail "no events for sess-alpha on shared.rs"
[ "$shared_beta"  -ge 1 ] || fail "no events for sess-beta on shared.rs"
pass "parallel sessions produced distinct event streams"

# --- 4. Heartbeat merging within a session ------------------------------------
log "test 4: repeated same-data heartbeats merge (duration grows)"
before=$(jq '[.[] | select(.data.session_id=="sess-alpha") | select(.data.file | endswith("lib.sh"))] | length' <<<"$evs")
fire_tool_event "sess-alpha" "$PWD" "Edit" "${PWD}/hooks/lib.sh"
fire_tool_event "sess-alpha" "$PWD" "Edit" "${PWD}/hooks/lib.sh"
fire_tool_event "sess-alpha" "$PWD" "Edit" "${PWD}/hooks/lib.sh"
evs=$(get_events)
after=$(jq '[.[] | select(.data.session_id=="sess-alpha") | select(.data.file | endswith("lib.sh"))] | length' <<<"$evs")
log "lib.sh sess-alpha events: before=${before} after=${after}"
# Merging means count should NOT grow by 3.
[ "$after" -le "$((before + 1))" ] || fail "heartbeats did not merge (before=${before} after=${after})"
pass "heartbeats merged within session"

# --- summary ------------------------------------------------------------------
total=$(jq 'length' <<<"$evs")
log "done — total events in bucket: ${total}"
echo
echo "Sample event:"
jq '.[0]' <<<"$evs"
