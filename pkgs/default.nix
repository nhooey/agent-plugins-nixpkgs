# Vendored third-party plugins: upstream ships no Nix package, so they're built here from the
# `flake = false` *-src inputs that flake.lock pins.
{
  pkgs,
  inputs,
  pluginLib,
}:
let
  inherit (pkgs) lib;
  mkClaudePlugin = pluginLib.mkClaudePlugin pkgs;
in
{
  # CC Safety Net blocks destructive shell commands and secret reads before Claude runs them.
  # Its own marketplace (kenryu42/cc-marketplace) follows the moving `plugin` branch; this
  # build changes only when flake.lock's cc-safety-net-src does.
  cc-safety-net = mkClaudePlugin {
    src = inputs.cc-safety-net-src;
    # Run the hook with this node rather than whatever `node` is first on PATH.
    postPatch = ''
      substituteInPlace hooks/hooks.json --replace-fail '"node ' '"${pkgs.nodejs}/bin/node '
    '';
  };

  # superpowers: brainstorming, planning, TDD, debugging and review workflows, with a
  # SessionStart hook that injects its `using-superpowers` skill. Its brainstorming server
  # fetches a logo from primeradiant.com unless SUPERPOWERS_DISABLE_TELEMETRY=1 is set where
  # Claude Code runs. Drop skills with `.override { excludeSkills = [ … ]; }`.
  superpowers = mkClaudePlugin { src = inputs.superpowers-src; };
}
# Trail of Bits plugins, each its own plugin under plugins/<name>/ of trailofbits/skills,
# packaged as trailofbits-<name>. None of these has hooks.
// lib.listToAttrs (
  map
    (name: {
      name = "trailofbits-${name}";
      value = mkClaudePlugin { src = "${inputs.trailofbits-skills-src}/plugins/${name}"; };
    })
    [
      # Fail-open, fallback-secret, weak-crypto and debug-feature audit (/insecure-defaults:audit).
      "insecure-defaults"
      # API misuse and footgun review, with per-language references.
      "sharp-edges"
      # Checks an implementation against its spec; writes spec-compliance/ in the repo.
      "spec-to-code-compliance"
    ]
)
