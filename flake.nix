{
  description = "ActivityWatch watcher for Claude Code sessions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, devenv }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (system: pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "aw-watcher-claudecode";
          version = "0.1.0";
          src = ./.;
          buildPhase = "true";
          installPhase = ''
            mkdir -p $out/share/aw-watcher-claudecode/hooks $out/bin
            cp hooks/lib.sh hooks/session-start.sh hooks/tool-event.sh \
              $out/share/aw-watcher-claudecode/hooks/
            cp install.sh uninstall.sh $out/share/aw-watcher-claudecode/
          '';
        };
      });

      # nix run . [-- --global|--project|...]  → deploys hooks to stable XDG path then registers
      # nix run .#uninstall                    → removes hook entries
      apps = forAllSystems (system: pkgs:
        let pkg = self.packages.${system}.default;
        in {
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
        });

      devShells = forAllSystems (system: pkgs: {
        default = devenv.lib.mkShell {
          inherit inputs pkgs;
          modules = [ ./devenv.nix ];
        };
      });

      homeManagerModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.aw-watcher-claudecode;
          pkg = self.packages.${pkgs.system}.default;
          stableDir = "${config.home.homeDirectory}/.local/share/aw-watcher-claudecode/hooks";
        in
        {
          options.programs.aw-watcher-claudecode = {
            enable = lib.mkEnableOption "aw-watcher-claudecode Claude Code hooks";
            server = lib.mkOption {
              type = lib.types.str;
              default = "http://127.0.0.1:5600";
              description = "ActivityWatch server URL";
            };
            pulsetime = lib.mkOption {
              type = lib.types.int;
              default = 120;
              description = "Heartbeat pulsetime in seconds";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ pkg ];

            # Stable symlink — path in settings.json never changes across store updates
            home.file.".local/share/aw-watcher-claudecode/hooks".source =
              "${pkg}/share/aw-watcher-claudecode/hooks";

            home.activation.aw-watcher-claudecode =
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                $DRY_RUN_CMD env HOOK_DIR="${stableDir}" ${pkgs.bash}/bin/bash \
                  "${pkg}/share/aw-watcher-claudecode/install.sh" \
                  --global \
                  ${lib.optionalString (cfg.server != "http://127.0.0.1:5600")
                    "--server ${cfg.server} "}\
                  ${lib.optionalString (cfg.pulsetime != 120)
                    "--pulsetime ${toString cfg.pulsetime} "}\
                  --target "$HOME/.claude/settings.json"
              '';
          };
        };
    };
}
