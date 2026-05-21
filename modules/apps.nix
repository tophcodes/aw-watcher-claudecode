{
  perSystem = { config, pkgs, ... }:
    let
      pkg = config.packages.default;
    in
    {
      apps = {
        default = {
          type = "app";
          program = toString (pkgs.writeShellScript "aw-watcher-claudecode-install" ''
            set -euo pipefail
            store_hooks="${pkg}/share/aw-watcher-claudecode/hooks"
            stable_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/aw-watcher-claudecode/hooks"
            mkdir -p "$stable_dir"
            cp -f "$store_hooks"/*.sh "$stable_dir/"
            HOOK_DIR="$stable_dir" exec ${pkgs.bash}/bin/bash \
              "${pkg}/share/aw-watcher-claudecode/install.sh" "$@"
          '');
        };
        uninstall = {
          type = "app";
          program = toString (pkgs.writeShellScript "aw-watcher-claudecode-uninstall" ''
            set -euo pipefail
            stable_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/aw-watcher-claudecode/hooks"
            HOOK_DIR="$stable_dir" exec ${pkgs.bash}/bin/bash \
              "${pkg}/share/aw-watcher-claudecode/uninstall.sh" "$@"
          '');
        };
      };
    };
}
