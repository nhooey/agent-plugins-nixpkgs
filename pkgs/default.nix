# Vendored third-party plugins: upstream ships no Nix package, so they're built here from the
# `flake = false` *-src inputs that flake.lock pins. First-party plugins, at the end, are passed
# through from their repositories' flakes, except agentree-statusline, built from its *-src input.
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
# First-party hooks-only plugins, each the `hooks-plugin` package of its skill repository: its
# hooks.json runs scripts copied in from the skills that document and test them.
// (
  let
    inherit (pkgs.stdenv.hostPlatform) system;
  in
  {
    coding-agent-skills-hooks = inputs.coding-agent-skills.packages.${system}.hooks-plugin;
    git-skills-hooks = inputs.git-skills.packages.${system}.hooks-plugin;
  }
)
# First-party plugins with code of their own: coding-agent-kanban-turns is its repository's
# `plugin` package, and agentree-statusline is built here.
// {
  coding-agent-kanban-turns =
    inputs.coding-agent-kanban-turns.packages.${pkgs.stdenv.hostPlatform.system}.plugin;

  # The agent tree status line: the session and its subagents as a live tree above the prompt.
  # Built here from its repository's plugin/ folder, whose own `plugin` package lacks the
  # passthru the module reads. `include` copies only what the engine loads, leaving out its
  # tests, tools and npm files, and needs `src` as a path: a flake input's outPath is a store
  # path string, so it's made a path, which reads the files the lock already fetched.
  agentree-statusline = mkClaudePlugin {
    src = /. + builtins.unsafeDiscardStringContext "${inputs.agentree-statusline-src}/plugin";
    include = [
      ".claude-plugin/plugin.json"
      "defaults"
      "hooks"
      "src"
      "types"
    ];
  };
}
