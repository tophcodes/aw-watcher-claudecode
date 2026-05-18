#!/usr/bin/env bash
# Shared functions for aw-watcher-claudecode hooks.
# Post events to a local ActivityWatch server using the heartbeat API.

set -u

: "${AW_SERVER:=http://127.0.0.1:5600}"
: "${AW_PULSETIME:=120}"
: "${AW_CLIENT:=aw-watcher-claudecode}"
: "${AW_BUCKET_TYPE:=app.editor.activity}"

AW_HOST="$(hostname -s 2>/dev/null || hostname)"
AW_BUCKET="${AW_CLIENT}_${AW_HOST}"

aw_iso_now() {
  # RFC3339 with millisecond precision, UTC.
  date -u +%Y-%m-%dT%H:%M:%S.%3NZ
}

aw_ensure_bucket() {
  if curl -fsS -o /dev/null "${AW_SERVER}/api/0/buckets/${AW_BUCKET}" 2>/dev/null; then
    return 0
  fi
  curl -fsS -X POST "${AW_SERVER}/api/0/buckets/${AW_BUCKET}" \
    -H 'Content-Type: application/json' \
    -d "{\"client\":\"${AW_CLIENT}\",\"type\":\"${AW_BUCKET_TYPE}\",\"hostname\":\"${AW_HOST}\"}" \
    >/dev/null 2>&1 || return 1
}

aw_heartbeat() {
  # $1: data JSON object (compact)
  local data="$1"
  local ts
  ts="$(aw_iso_now)"
  curl -fsS -X POST \
    "${AW_SERVER}/api/0/buckets/${AW_BUCKET}/heartbeat?pulsetime=${AW_PULSETIME}" \
    -H 'Content-Type: application/json' \
    -d "{\"timestamp\":\"${ts}\",\"duration\":0,\"data\":${data}}" \
    >/dev/null 2>&1 || return 1
}

aw_detect_language() {
  local f="$1"
  local ext="${f##*.}"
  case "$ext" in
    rs) echo rust ;;
    ts) echo typescript ;;
    tsx) echo typescriptreact ;;
    js|mjs|cjs) echo javascript ;;
    jsx) echo javascriptreact ;;
    py) echo python ;;
    rb) echo ruby ;;
    go) echo go ;;
    nix) echo nix ;;
    hcl|tf) echo hcl ;;
    sh|bash) echo shell ;;
    fish) echo fish ;;
    zsh) echo shell ;;
    md|markdown) echo markdown ;;
    json) echo json ;;
    yaml|yml) echo yaml ;;
    toml) echo toml ;;
    html|htm) echo html ;;
    css) echo css ;;
    scss|sass) echo scss ;;
    sql) echo sql ;;
    c|h) echo c ;;
    cpp|cc|cxx|hpp) echo cpp ;;
    java) echo java ;;
    kt|kts) echo kotlin ;;
    swift) echo swift ;;
    lua) echo lua ;;
    ex|exs) echo elixir ;;
    erl) echo erlang ;;
    *) echo plaintext ;;
  esac
}

aw_detect_project() {
  # Walk up looking for .git, return basename of repo root.
  # Fallback: basename of starting dir.
  local dir="$1"
  local start="$dir"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -e "$dir/.git" ]; then
      basename "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  basename "$start"
}
