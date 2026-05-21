# Dev

```sh
devenv shell        # bash, curl, jq, aw-server-rust
devenv up           # aw-server on :5600
```

## Tests

```sh
nix flake check             # install logic (no server needed)
./tests/e2e.sh              # full end-to-end (spins up aw-server on :5699)
```

`nix flake check` runs `tests/install_test.sh`: fresh install, idempotency,
existing-config preservation, `--server`/`--pulsetime` baking, `--dry-run`,
uninstall, backup creation.

`tests/e2e.sh` spawns an isolated aw-server, pipes synthetic hook payloads,
asserts bucket creation, field population, parallel-session distinctness, and
heartbeat merging. Output: `[PASS]` / `[FAIL]` lines + sample event.
