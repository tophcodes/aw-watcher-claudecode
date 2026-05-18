# aw-watcher-claudecode

ActivityWatch watcher for Claude Code sessions. Reports the file,
project, language, and session being worked on to a local
`aw-server` via the heartbeat API.

Implemented as plain Claude Code hook scripts — no daemon, no
plugin runtime. Each tool invocation in Claude Code fires a
`PreToolUse` hook which posts a heartbeat.

## Schema

Bucket: `aw-watcher-claudecode_<hostname>` (type `app.editor.activity`).

Event data:

```json
{
  "file": "/abs/path/to/file",
  "project": "repo-basename",
  "language": "rust",
  "editor": "claude-code",
  "session_id": "<claude-session-uuid>"
}
```

`session_id` is in the heartbeat data on purpose: two parallel
Claude Code sessions editing the same file remain two distinct
event streams in the bucket instead of being merged.

## Install

1. Pick an absolute path to this checkout (e.g.
   `/home/you/Projects/aw-watcher-claudecode`).
2. Merge `settings.example.json` into your Claude Code settings
   (`~/.claude/settings.json` for global, or per-project
   `.claude/settings.json`), adjusting the `command` paths.
3. Ensure a local `aw-server` is reachable at
   `http://127.0.0.1:5600` (default), or override:
   ```
   export AW_SERVER=http://other-host:5600
   export AW_PULSETIME=120   # seconds; heartbeat merge window
   ```

The watcher creates its bucket on first event — no extra setup.

## Hooks

| Hook | Purpose |
| --- | --- |
| `hooks/session-start.sh` | Wired to `SessionStart`. Ensures the bucket exists and emits a marker heartbeat. |
| `hooks/tool-event.sh` | Wired to `PreToolUse`. Posts a heartbeat with the file being acted on. |

Hooks read the Claude Code hook payload JSON from stdin
(`session_id`, `cwd`, `tool_name`, `tool_input.file_path`).

## Parallel sessions

Yes — the watcher is parallel-safe by design.

- Heartbeat merging in ActivityWatch only fires when two events
  share identical `data` AND fall inside `pulsetime`.
- `session_id` is part of `data`, so two sessions never collapse
  into one event even if they edit the same file at the same
  moment.
- Each hook invocation is its own short-lived process; there is
  no shared in-memory state to race on.

## Dev environment

```
devenv shell        # bash, curl, jq, aw-server-rust
devenv up           # run aw-server on :5600
./tests/e2e.sh      # end-to-end test (spins up isolated server on :5699)
```

## Tests

`tests/e2e.sh`:

1. Spawns an isolated `aw-server` on port 5699 with its own
   `XDG_*` dirs so it never touches your real AW data.
2. Pipes synthetic Claude Code hook payloads (`session_id`,
   `cwd`, `tool_name`, `tool_input.file_path`) into the hook
   scripts.
3. Curls `aw-server` back to assert:
   - bucket was created
   - file / project / language fields are populated
   - parallel sessions on the same file produce distinct events
   - same-data heartbeats within `pulsetime` merge

Output is a series of `[PASS]` / `[FAIL]` lines plus a sample
event from the bucket.
