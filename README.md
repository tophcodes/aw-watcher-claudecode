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

### NixOS / home-manager (recommended)

Add to your flake inputs and enable the module:

```nix
# flake.nix
inputs.aw-watcher-claudecode.url = "github:tophcodes/aw-watcher-claudecode";

# home.nix / your home-manager module
{ inputs, ... }: {
  imports = [ inputs.aw-watcher-claudecode.homeManagerModules.default ];

  programs.aw-watcher-claudecode = {
    enable = true;
    # server = "http://127.0.0.1:5600";  # default
    # pulsetime = 120;                   # default, in seconds
  };
}
```

`home-manager switch` deploys the hook scripts to a stable path under
`~/.local/share/aw-watcher-claudecode/hooks/` and merges the hook
entries into `~/.claude/settings.json`. Idempotent — re-switching is
a no-op. The paths in settings.json are stable across store updates.

### nix run (no clone needed)

```sh
nix run github:tophcodes/aw-watcher-claudecode             # → ~/.claude/settings.json
nix run github:tophcodes/aw-watcher-claudecode -- --project .
nix run github:tophcodes/aw-watcher-claudecode -- --dry-run
nix run github:tophcodes/aw-watcher-claudecode -- --server http://aw.lan:5600 --pulsetime 60
```

Copies hooks to `~/.local/share/aw-watcher-claudecode/hooks/` (stable
path) then merges entries into the target settings file.

Uninstall:

```sh
nix run github:tophcodes/aw-watcher-claudecode#uninstall
```

### Manual (git clone)

```sh
git clone https://github.com/tophcodes/aw-watcher-claudecode.git
cd aw-watcher-claudecode
./install.sh                 # → ~/.claude/settings.json
./install.sh --project .     # ./.claude/settings.json
./install.sh --local .       # ./.claude/settings.local.json
./install.sh --target /path/to.json
./install.sh --dry-run
./install.sh --server http://aw.example.lan:5600 --pulsetime 60
```

Uninstall:

```sh
./uninstall.sh
./uninstall.sh --target /path/to.json
```

Removes only the entries that reference this checkout's hooks.
Other hooks and settings stay put.

The watcher creates its bucket on first event — no extra setup.

Default server: `http://127.0.0.1:5600`. Default pulsetime: `120s`.

### Manual (no script)

Merge `settings.example.json` into your settings.json, replacing
the absolute paths with your actual hooks location.

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
nix develop         # or: direnv allow (uses flake devShell)
devenv up           # run aw-server on :5600
./tests/e2e.sh      # end-to-end test (spins up isolated server on :5699)
```

## Tests

```sh
./tests/install_test.sh    # jq merge logic + uninstall (no server needed)
./tests/e2e.sh             # spins up aw-server, fires hooks, asserts via curl
```

`tests/install_test.sh` covers fresh install, existing-config
preservation, idempotency, `--server`/`--pulsetime` env baking,
`--dry-run`, uninstall, and backup creation.

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
