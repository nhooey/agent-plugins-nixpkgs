# agent-plugins-nixpkgs

Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through
Claude Code's managed settings. The plugins' code changes only when this flake's lock does, and
no Claude session or user setting can turn them off.

Its sibling for skills is [`skillspkgs`](https://github.com/nhooey/skillspkgs).

## Packages

| Package                                | Plugin                                                                                                                                                                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cc-safety-net`                        | [CC Safety Net](https://github.com/kenryu42/cc-safety-net): blocks destructive shell commands and secret reads. Its hook runs with Nix's `node`.                                                                       |
| `superpowers`                          | [superpowers](https://github.com/obra/superpowers): brainstorming, planning, TDD, debugging and review workflows. Its SessionStart hook injects `using-superpowers`; set `SUPERPOWERS_DISABLE_TELEMETRY=1` to stop its logo fetch. |
| `trailofbits-insecure-defaults`        | [insecure-defaults](https://github.com/trailofbits/skills/tree/main/plugins/insecure-defaults): audits fail-open paths, fallback secrets, weak crypto and debug features.                                               |
| `trailofbits-sharp-edges`              | [sharp-edges](https://github.com/trailofbits/skills/tree/main/plugins/sharp-edges): reviews API misuse and footguns, with per-language references.                                                                      |
| `trailofbits-spec-to-code-compliance`  | [spec-to-code-compliance](https://github.com/trailofbits/skills/tree/main/plugins/spec-to-code-compliance): checks an implementation against its spec.                                                                  |

Vendored plugins come from `flake = false` inputs, so `flake.lock` pins them. Update one with:

```bash
nix flake update cc-safety-net-src
```

To load a plugin without some of its skills, override it:

```nix
agent-plugins-nixpkgs.packages.${system}.superpowers.override {
  excludeSkills = [ "diagnosing-superpowers" ];
}
```

A name the plugin doesn't have under `skills/` fails the build, so an upstream rename can't bring a
skill back unnoticed.

To load plugins for one session without installing them, pass each package's store path to
`claude --plugin-dir`.

First-party plugin repositories should export their plugin directory as a flake package of their
own; this flake then takes them as inputs and passes them through.

## nix-darwin module

```nix
{
  inputs.agent-plugins-nixpkgs.url = "github:nhooey/agent-plugins-nixpkgs";

  # In a nix-darwin configuration:
  imports = [ inputs.agent-plugins-nixpkgs.darwinModules.default ];
  services.agent-plugins = {
    enable = true;
    plugins = [ inputs.agent-plugins-nixpkgs.packages.aarch64-darwin.cc-safety-net ];
    # Optional: CC Safety Net rulebooks, served read-only from the store.
    ccSafetyNet.rulebooks = [
      {
        rulebook_version = 1;
        name = "local-git-guards";
        version = "1.0.0";
        allowed_commands = [ "git" ];
        rules = [
          {
            name = "block-git-add-all";
            command = "git";
            subcommand = "add";
            block_args = [ "-A" "--all" ];
            reason = "Stage files by path.";
          }
        ];
      }
    ];
  };
}
```

On activation it writes `/Library/Application Support/ClaudeCode/managed-settings.d/<dropInName>`,
owned by root, which:

- registers a marketplace, `<marketplaceName>`, built in the store from the listed plugins
  (`extraKnownMarketplaces`, `"source": "directory"`)
- enables each plugin as `<plugin>@<marketplaceName>` (`enabledPlugins`)
- with rulebooks, sets `env.CC_SAFETY_NET_HOME` to a store folder holding them as real files,
  since Safety Net refuses symlinked config files. Safety Net still writes its audit log to
  `~/.cc-safety-net/logs`.
- merges in `extraSettings` last, so it can add any other managed setting or override these.

The other options of `services.agent-plugins`:

| Option             | Default                   | Meaning                                              |
| ------------------ | ------------------------- | ---------------------------------------------------- |
| `marketplaceName`  | `"nix-pinned"`            | Name of the generated marketplace.                   |
| `marketplaceOwner` | `"nix"`                   | Owner name written into the marketplace manifest.    |
| `extraSettings`    | `{ }`                     | More managed settings merged into the drop-in.       |
| `dropInName`       | `"40-agent-plugins.json"` | File name of the drop-in under `managed-settings.d`. |

Rulebooks published by first-party skill repositories are flake outputs under
`safetyNetRulebooks`, ready for `ccSafetyNet.rulebooks`:

```nix
ccSafetyNet.rulebooks = [
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.git-avoid-sweeping-operations
];
```

`git-avoid-sweeping-operations` comes from [`git-skills`](https://github.com/nhooey/git-skills).

Nix doesn't track the drop-in: disabling the module leaves it in place, so delete it with `sudo`
afterwards.

## Library

- `lib.mkClaudePlugin pkgs { src, excludeSkills ? [ ], postPatch ? "" }`: copies a plugin directory
  into the store, removes the `skills/` directories named in `excludeSkills`, runs `postPatch`, and
  reads its name and version from `.claude-plugin/plugin.json`. The result is overridable with
  `.override`.
- `lib.mkMarketplace pkgs { name, owner, plugins }`: a local marketplace listing the plugins.
- `lib.mkSafetyNetHome pkgs rulebooks`: a CC Safety Net home folder for `CC_SAFETY_NET_HOME`.

## Checks

`nix flake check` runs the checks in `tests/`, one file per concern, with shared shell in
`tests/lib/helpers.sh`:

- `vendored-plugins`: each plugin's name, version and derivation name come from its manifest,
  Safety Net's hook runs the pinned node, and `excludeSkills` removes exactly the skill it names.
- `exclude-skills-unknown-name`: naming a skill the plugin lacks fails the build.
- `marketplace`: `mkMarketplace` lists each plugin's name, source and version, and links each to
  its build.
- `safety-net-home`: `mkSafetyNetHome` writes `rule.json` and each rulebook as a regular file.
- `cc-safety-net-hook`: the hook, run the way Claude Code runs it, denies a rule from
  `safetyNetRulebooks.git-avoid-sweeping-operations`, a rule from a rulebook written in the check,
  and a built-in rule, each by name, and allows `git status`.
- `darwin-module`: the nix-darwin module, evaluated on its own, writes a drop-in that enables each
  plugin from the generated marketplace, points `CC_SAFETY_NET_HOME` at the rulebooks and merges
  `extraSettings`; disabled, it writes nothing.
- `formatting`: fails if `nix fmt` (treefmt running nixfmt) would change a file.
