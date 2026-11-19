# The flake's checks, one file per concern. Each takes the flake's `self` and the `pkgs` of the
# system being checked (agent-plugins-cli also the dev shell's tool); tests/lib/helpers.sh holds the shell they share.
{
  self,
  pkgs,
  agent-plugins,
}:
let
  args = {
    inherit self pkgs;
    helpers = ./lib/helpers.sh;
  };
in
{
  vendored-plugins = import ./vendored-plugins.nix args;
  first-party-plugins = import ./first-party-plugins.nix args;
  exclude-skills-unknown-name = import ./exclude-skills-unknown-name.nix args;
  marketplace = import ./marketplace.nix args;
  safety-net-home = import ./safety-net-home.nix args;
  cc-safety-net-hook = import ./cc-safety-net-hook.nix args;
  safety-net-rulebooks = import ./safety-net-rulebooks.nix args;
  darwin-module = import ./darwin-module.nix args;
  claude-plugin-dev = import ./claude-plugin-dev.nix args;
  agent-plugins-cli = import ./agent-plugins-cli.nix { inherit self pkgs agent-plugins; };
}
