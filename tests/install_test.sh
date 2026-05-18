#!/usr/bin/env bash
# Tests for install.sh / uninstall.sh:
#   - merges into an empty settings.json
#   - preserves unrelated existing settings
#   - idempotent (second run = no duplicates)
#   - --server / --pulsetime bake env into command strings
#   - uninstall removes our entries without touching others

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${REPO_ROOT}/tests/_run_install"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"

log() { printf '\033[1;34m[install-test]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
pass() { printf '\033[1;32m[PASS]\033[0m %s\n' "$*"; }

HOOK_DIR="${REPO_ROOT}/hooks"

# ---------- case 1: empty settings ----------
T1="${RUN_DIR}/case1.json"
bash "${REPO_ROOT}/install.sh" --target "$T1" >/dev/null
jq -e --arg p "${HOOK_DIR}/session-start.sh" \
  '.hooks.SessionStart[0].hooks[0].command | contains($p)' "$T1" >/dev/null \
  || fail "SessionStart hook not installed"
jq -e --arg p "${HOOK_DIR}/tool-event.sh" \
  '.hooks.PreToolUse[0].hooks[0].command | contains($p)' "$T1" >/dev/null \
  || fail "PreToolUse hook not installed"
jq -e '.hooks.PreToolUse[0].matcher == "Edit|MultiEdit|Write|Read|NotebookEdit|Glob|Grep|Bash"' "$T1" >/dev/null \
  || fail "matcher missing"
pass "fresh install populates hooks"

# ---------- case 2: preserves existing unrelated config ----------
T2="${RUN_DIR}/case2.json"
cat >"$T2" <<'EOF'
{
  "model": "claude-opus-4-7",
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "/bin/true" }] }
    ]
  }
}
EOF
bash "${REPO_ROOT}/install.sh" --target "$T2" >/dev/null
jq -e '.model == "claude-opus-4-7"' "$T2" >/dev/null || fail "model field clobbered"
jq -e '.permissions.allow[0] == "Bash(ls:*)"' "$T2" >/dev/null || fail "permissions clobbered"
jq -e '.hooks.Stop[0].hooks[0].command == "/bin/true"' "$T2" >/dev/null || fail "existing Stop hook lost"
jq -e '.hooks.SessionStart | length == 1' "$T2" >/dev/null || fail "SessionStart not added"
jq -e '.hooks.PreToolUse | length == 1' "$T2" >/dev/null || fail "PreToolUse not added"
pass "existing config preserved"

# ---------- case 3: idempotency ----------
T3="${RUN_DIR}/case3.json"
bash "${REPO_ROOT}/install.sh" --target "$T3" >/dev/null
bash "${REPO_ROOT}/install.sh" --target "$T3" >/dev/null
bash "${REPO_ROOT}/install.sh" --target "$T3" >/dev/null
ss_count=$(jq '.hooks.SessionStart | length' "$T3")
te_count=$(jq '.hooks.PreToolUse | length' "$T3")
[ "$ss_count" = "1" ] || fail "SessionStart duplicated (count=${ss_count})"
[ "$te_count" = "1" ] || fail "PreToolUse duplicated (count=${te_count})"
pass "re-running install is a no-op"

# ---------- case 4: --server / --pulsetime bake env ----------
T4="${RUN_DIR}/case4.json"
bash "${REPO_ROOT}/install.sh" \
  --target "$T4" \
  --server "http://aw.example.lan:5600" \
  --pulsetime 60 >/dev/null
cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$T4")
echo "$cmd" | grep -q "AW_SERVER=http://aw.example.lan:5600" \
  || fail "AW_SERVER not baked (got: $cmd)"
echo "$cmd" | grep -q "AW_PULSETIME=60" \
  || fail "AW_PULSETIME not baked (got: $cmd)"
pass "--server / --pulsetime bake env vars"

# ---------- case 5: dry-run writes nothing ----------
T5="${RUN_DIR}/case5.json"
bash "${REPO_ROOT}/install.sh" --target "$T5" --dry-run >"${RUN_DIR}/case5.out"
[ ! -f "$T5" ] || fail "dry-run wrote a file"
jq -e '.hooks.SessionStart' "${RUN_DIR}/case5.out" >/dev/null \
  || fail "dry-run output not valid JSON"
pass "--dry-run prints, does not write"

# ---------- case 6: uninstall ----------
T6="${RUN_DIR}/case6.json"
cat >"$T6" <<'EOF'
{
  "model": "foo",
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "/bin/true" }] }
    ]
  }
}
EOF
bash "${REPO_ROOT}/install.sh" --target "$T6" >/dev/null
bash "${REPO_ROOT}/uninstall.sh" --target "$T6" >/dev/null
jq -e '.model == "foo"' "$T6" >/dev/null || fail "uninstall clobbered model"
jq -e '.hooks.Stop[0].hooks[0].command == "/bin/true"' "$T6" >/dev/null \
  || fail "uninstall clobbered Stop hook"
jq -e '(.hooks.SessionStart // []) | length == 0' "$T6" >/dev/null \
  || fail "uninstall left SessionStart entry"
jq -e '(.hooks.PreToolUse // []) | length == 0' "$T6" >/dev/null \
  || fail "uninstall left PreToolUse entry"
pass "uninstall removes our entries and keeps the rest"

# ---------- case 7: backup file is created ----------
T7="${RUN_DIR}/case7.json"
echo '{"existing":true}' >"$T7"
bash "${REPO_ROOT}/install.sh" --target "$T7" >/dev/null
ls "${T7}".bak.* >/dev/null 2>&1 || fail "no backup file created"
pass "backup file written on install"

log "all install/uninstall tests passed"
