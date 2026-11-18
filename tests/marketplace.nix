# mkMarketplace lists each plugin by name, relative source and version, and holds each name as a
# real copy of that exact build, with no symlinks.
{
  self,
  pkgs,
  helpers,
}:
let
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  # A plugin-like derivation with no version in passthru.
  bare = pkgs.runCommand "bare-plugin" { passthru.claudePluginName = "bare"; } "mkdir -p $out";
  marketplace = self.lib.mkMarketplace pkgs {
    name = "check-market";
    owner = "check-owner";
    plugins = [
      p.cc-safety-net
      p.superpowers
      bare
    ];
  };
  want = builtins.toJSON {
    name = "check-market";
    owner.name = "check-owner";
    plugins = [
      {
        name = "cc-safety-net";
        source = "./cc-safety-net";
        inherit (p.cc-safety-net) version;
      }
      {
        name = "superpowers";
        source = "./superpowers";
        inherit (p.superpowers) version;
      }
      {
        name = "bare";
        source = "./bare";
        version = "0";
      }
    ];
  };
in
pkgs.runCommand "check-marketplace" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}
  m=${marketplace}/.claude-plugin/marketplace.json
  diff <(jq -S . $m) <(echo ${pkgs.lib.escapeShellArg want} | jq -S .) || fail "marketplace.json differs from the expected listing"
  diff -r ${marketplace}/cc-safety-net ${p.cc-safety-net} || fail "cc-safety-net copy"
  diff -r ${marketplace}/superpowers ${p.superpowers} || fail "superpowers copy"
  diff -r ${marketplace}/bare ${bare} || fail "bare copy"
  test -z "$(find ${marketplace} -type l)" || fail "symlinks in the marketplace"
  touch $out
''
