# Dev

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

`aw-server-rust` muss im PATH sein (z.B. `nix shell nixpkgs#aw-server-rust`).
