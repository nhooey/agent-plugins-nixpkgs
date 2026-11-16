# The flake's checks, one file per concern. Each takes the flake's `self` and the `pkgs` of the
# system being checked; tests/lib/helpers.sh holds the shell they share.
{ self, pkgs }:
let
  args = {
    inherit self pkgs;
    helpers = ./lib/helpers.sh;
  };
in
{
  vendored-plugins = import ./vendored-plugins.nix args;
  cc-safety-net-hook = import ./cc-safety-net-hook.nix args;
}
