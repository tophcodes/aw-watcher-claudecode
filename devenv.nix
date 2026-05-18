{pkgs, ...}: {
  packages = with pkgs; [
    aw-server-rust
    jq
    curl
    bash
    coreutils
    netcat-gnu
  ];

  enterShell = ''
    echo "aw-watcher-claudecode dev shell"
    echo "  run tests:   ./tests/e2e.sh"
    echo "  start aw:    devenv up   (server on :5600)"
  '';

  processes.aw-server.exec = ''
    aw-server --host 127.0.0.1 --port 5600
  '';
}
