{ self, ... }:
{
  perSystem = { pkgs, ... }: {
    checks.install-test = pkgs.runCommand "aw-watcher-claudecode-install-test"
      { src = self; buildInputs = [ pkgs.bash pkgs.jq pkgs.coreutils ]; }
      ''
        cp -r $src src
        chmod -R u+w src
        cd src
        bash tests/install_test.sh
        touch $out
      '';
  };
}
