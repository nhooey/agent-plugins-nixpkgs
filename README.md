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

Vendored plugins come from `flake = false` inputs, so `flake.lock` pins them. Update one with
`agent-plugins update cc-safety-net-src` in the dev shell, or all of them with
`agent-plugins update`.

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
own; this flake then takes them as inputs and passes them through. These come through so far,
each a hooks-only plugin whose `hooks.json` runs scripts copied in from the skills that document
and test them:

| Package                     | Plugin                                                                                                                                                                                                                                                                                                                  |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `coding-agent-skills-hooks` | The `hooks-plugin` package of [`coding-agent-skills`](https://github.com/nhooey/coding-agent-skills): `session-build-limits.sh` at SessionStart, the scratchpad guard before Bash, Write and Edit and at SubagentStart, the memory-write reminder, the plans check, the browser check, and the reply lint at Stop. |
| `git-skills-hooks`          | The `hooks-plugin` package of [`git-skills`](https://github.com/nhooey/git-skills): `pull-request-sync-check.sh` after Bash, which flags an open pull request whose title or body has drifted from its commit.                                                                                                       |
| `coding-agent-kanban-turns` | The `plugin` package of [`coding-agent-kanban-turns`](https://github.com/nhooey/coding-agent-kanban-turns): the kanban turn responses' mod, which draws clickable answers for Decide items and registers the `kanban_options` tool. |

An update to any of them is a lock bump here (`agent-plugins update coding-agent-skills`,
`agent-plugins update git-skills` or `agent-plugins update coding-agent-kanban-turns`), then a lock bump of this flake in MyNixOS, and a switch.
Claude Code loads the new build at the next session start.

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
- enables each plugin as `<plugin>@<marketplaceName>` (`enabledPlugins`), except those named in
  `unmanaged`
- with rulebooks, sets `env.CC_SAFETY_NET_HOME` to a store folder holding them as real files,
  since Safety Net refuses symlinked config files. Safety Net still writes its audit log to
  `~/.cc-safety-net/logs`.
- merges in `extraSettings` last, so it can add any other managed setting or override these.

The other options of `services.agent-plugins`:

| Option             | Default                   | Meaning                                              |
| ------------------ | ------------------------- | ---------------------------------------------------- |
| `unmanaged`        | `[ ]`                     | Plugin names left out of `enabledPlugins`.           |
| `marketplaceName`  | `"nix-pinned"`            | Name of the generated marketplace.                   |
| `marketplaceOwner` | `"nix"`                   | Owner name written into the marketplace manifest.    |
| `extraSettings`    | `{ }`                     | More managed settings merged into the drop-in.       |
| `dropInName`       | `"40-agent-plugins.json"` | File name of the drop-in under `managed-settings.d`. |

Rulebooks published by first-party skill repositories are flake outputs under
`safetyNetRulebooks`, ready for `ccSafetyNet.rulebooks`:

```nix
ccSafetyNet.rulebooks = [
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.git-avoid-sweeping-operations
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.shell-hygiene
];
```

- `git-avoid-sweeping-operations` comes from [`git-skills`](https://github.com/nhooey/git-skills).
- `shell-hygiene` comes from [`shell-skills`](https://github.com/nhooey/shell-skills): it blocks
  killing processes by pattern, machine-wide installs, prunes, service and settings changes,
  common numeric `chmod` modes, and `op read` and `gh auth token`.

Nix doesn't track the drop-in: disabling the module leaves it in place, so delete it with `sudo`
afterwards.

## Developing a plugin

A managed `enabledPlugins` entry beats every other source, and Claude Code matches plugins by
manifest name, so while the drop-in enables `<plugin>@nix-pinned`, `claude --plugin-dir` on that
plugin's checkout is ignored ("plugin is locked by managed settings"). To work on one of the
pinned plugins, take it out of managed settings and run its checkout instead:

1. Name it in `unmanaged`, and switch:

   ```nix
   services.agent-plugins.unmanaged = [ "coding-agent-kanban-turns" ];
   ```

   Every `enabledPlugins` entry of that name leaves the drop-in, under any marketplace and
   including those `extraSettings` adds, but the plugin stays in the marketplace. So its pinned
   build is still there to enable, in user settings, for sessions that don't load the checkout;
   a `--plugin-dir` copy replaces it in the sessions that do. Every other plugin stays managed.
   A name that matches no plugin in `plugins` fails the build, so a typo can't silently do
   nothing.

2. In the plugin's repository, run `claude-plugin-dev` from its dev shell. It:

   - finds each local plugin in the repository's `.claude-plugin/marketplace.json`, resolving
     each relative `source` against the repository root
   - reads the managed settings: `managed-settings.json` and every `*.json` in
     `managed-settings.d/`, under `/Library/Application Support/ClaudeCode` or
     `CLAUDE_PLUGIN_DEV_MANAGED_SETTINGS`
   - stops without starting `claude` if any entry there, `true` or `false`, names one of those
     plugins (by name, ignoring case, as Claude Code compares them). For an entry in a drop-in
     under the module's marketplace (`nix-pinned`, or `CLAUDE_PLUGIN_DEV_MARKETPLACE`), it prints
     the `unmanaged` line to add; for any other, it says to remove that entry from its file.
   - otherwise starts `claude` with a `--plugin-dir` for each plugin, followed by its own
     arguments

3. Edit the plugin in place. A mod's hooks module reloads on save, and `/reload-plugins` picks up
   hooks, skills, commands and agents without a restart.

Claude Code writes TypeScript types for a `--plugin-dir` mod into
`<plugin>/.claude-plugin/types/`, so add that folder to the plugin repository's `.gitignore`.

The command comes from `lib.claudePluginDevCommand pkgs`, a
[numtide devshell](https://github.com/numtide/devshell) `commands` entry:

```nix
devshells.default.commands = [ (claudePlugins.claudePluginDevCommand pkgs) ];
```

where `claudePlugins` is this flake's `lib`, or `import "${inputs.agent-plugins-nixpkgs}/lib" {
inherit lib; }` from a `flake = false` input. Another kind of shell takes the command from the
entry's `package`: `packages = [ (claudePlugins.claudePluginDevCommand pkgs).package ];`. It runs
the `claude` on the caller's `PATH` and adds nothing to the `PATH` that `claude` sees.

## Library

- `lib.mkClaudePlugin pkgs { src, excludeSkills ? [ ], postPatch ? "" }`: copies a plugin directory
  into the store, removes the `skills/` directories named in `excludeSkills`, runs `postPatch`, and
  reads its name and version from `.claude-plugin/plugin.json`. The result is overridable with
  `.override`.
- `lib.mkMarketplace pkgs { name, owner, plugins }`: a local marketplace listing the plugins.
- `lib.mkSafetyNetHome pkgs rulebooks`: a CC Safety Net home folder for `CC_SAFETY_NET_HOME`.
- `lib.claudePluginDevCommand pkgs`: the `claude-plugin-dev` dev shell command, as a numtide
  devshell `commands` entry whose `package` is the command itself; see
  [Developing a plugin](#developing-a-plugin).

## Dev shell

`nix develop` enters a [numtide devshell](https://github.com/numtide/devshell) and installs the
agent skills in `.agents/skills/`; `menu` lists its commands. Its tool, `agent-plugins`, takes the
command tokens `build`, `check`, `fmt`, `list`, `update` and `skills`, each with `--help`, and
`--dry-run` prints the `nix` commands a token runs without running them.

## Checks

`agent-plugins check`, or `nix flake check`, runs the checks in `tests/`, one file per concern,
with shared shell in `tests/lib/helpers.sh`:

- `vendored-plugins`: each plugin's name, version and derivation name come from its manifest,
  Safety Net's hook runs the pinned node, and `excludeSkills` removes exactly the skill it names.
- `first-party-plugins`: each passed-through hooks plugin is named by its manifest, and holds
  every script its `hooks.json` runs.
- `exclude-skills-unknown-name`: naming a skill the plugin lacks fails the build.
- `marketplace`: `mkMarketplace` lists each plugin's name, source and version, and links each to
  its build.
- `safety-net-home`: `mkSafetyNetHome` writes `rule.json` and each rulebook as a regular file.
- `cc-safety-net-hook`: the hook, run the way Claude Code runs it, denies a rule from
  `safetyNetRulebooks.git-avoid-sweeping-operations`, a rule from a rulebook written in the check,
  and a built-in rule, each by name, and allows `git status`.
- `safety-net-rulebooks`: each rulebook in `safetyNetRulebooks` passes its own `tests` fixtures
  through the hook: a `blocked` fixture is denied by its own rule, an `allowed` one isn't denied,
  and every rule has a `blocked` fixture.
- `darwin-module`: the nix-darwin module, evaluated on its own, writes a drop-in that enables each
  plugin from the generated marketplace but the `unmanaged` ones, which stay in the marketplace,
  points `CC_SAFETY_NET_HOME` at the rulebooks and merges `extraSettings`, which can't bring an
  unmanaged plugin back; disabled, it writes nothing. An `unmanaged` name that matches no plugin
  fails an assertion.
- `claude-plugin-dev`: the command's unit tests pass, and run in a fixture repository with a stub
  `claude`, it passes a `--plugin-dir` per local plugin and then its own arguments, or, with
  fixture managed settings naming one of those plugins, exits non-zero without starting
  `claude`, printing the `unmanaged` line for the module's entries and a removal for any other.
- `agent-plugins-cli`: the `agent-plugins` tool's unit tests of its argument parsing and the `nix`
  commands each token plans pass, its `--help` lists every token, and `update` rejects an input
  `flake.lock` lacks.
- `formatting`: fails if `nix fmt` (treefmt running nixfmt and ruff) would change a file.
