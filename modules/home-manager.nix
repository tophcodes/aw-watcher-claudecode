{ self, ... }:
{
  flake.homeManagerModules.default =
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
}
