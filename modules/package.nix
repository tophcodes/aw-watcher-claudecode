{ self, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.default = pkgs.stdenv.mkDerivation {
      pname = "aw-watcher-claudecode";
      version = "0.1.0";
      src = self;
      buildPhase = "true";
      installPhase = ''
        mkdir -p $out/share/aw-watcher-claudecode/hooks
        cp hooks/lib.sh hooks/session-start.sh hooks/tool-event.sh \
          $out/share/aw-watcher-claudecode/hooks/
        cp install.sh uninstall.sh $out/share/aw-watcher-claudecode/
      '';
    };
  };
}
