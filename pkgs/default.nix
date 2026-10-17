# Vendored third-party plugins: upstream ships no Nix package, so they're built here from the
# `flake = false` *-src inputs that flake.lock pins.
{
  pkgs,
  inputs,
  pluginLib,
}:
{
  # CC Safety Net blocks destructive shell commands and secret reads before Claude runs them.
  # Its own marketplace (kenryu42/cc-marketplace) follows the moving `plugin` branch; this
  # build changes only when flake.lock's cc-safety-net-src does.
  cc-safety-net = pluginLib.mkClaudePlugin pkgs {
    src = inputs.cc-safety-net-src;
    # Run the hook with this node rather than whatever `node` is first on PATH.
    postPatch = ''
      substituteInPlace hooks/hooks.json --replace-fail '"node ' '"${pkgs.nodejs}/bin/node '
    '';
  };
}
