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
- enables each plugin as `<plugin>@<marketplaceName>` (`enabledPlugins`)
- with rulebooks, sets `env.CC_SAFETY_NET_HOME` to a store folder holding them as real files,
  since Safety Net refuses symlinked config files. Safety Net still writes its audit log to
  `~/.cc-safety-net/logs`.
- sets `env.AGENT_HOOK_MODES` to `hook-modes.json` in the store, written from `hookModes`
  ([Hook modes](#hook-modes)); with no `hookModes` it holds `{}`.
- merges in `extraSettings` last, so it can add any other managed setting or override these.

The other options of `services.agent-plugins`:

| Option             | Default                   | Meaning                                              |
| ------------------ | ------------------------- | ---------------------------------------------------- |
| `marketplaceName`  | `"nix-pinned"`            | Name of the generated marketplace.                   |
| `marketplaceOwner` | `"nix"`                   | Owner name written into the marketplace manifest.    |
| `hookModes`        | `{ }`                     | Each hook's mode by name: `off`, `remind` or `deny`. |
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
  killing processes by pattern, `rsync --delete`, recursive `chmod` and `chown`, machine-wide
  installs, prunes, service and settings changes, common numeric `chmod` modes, and `op read`
  and `gh auth token`.

Nix doesn't track the drop-in: disabling the module leaves it in place, so delete it with `sudo`
afterwards.

### Hook modes

Every hook that can deny or replace an action has a mode, set by name in `hookModes`:

| Mode     | The hook                                                                |
| -------- | ----------------------------------------------------------------------- |
| `deny`   | denies the action, with its reason.                                     |
| `remind` | adds context saying what it would have denied, and lets the action run. |
| `off`    | exits at once.                                                          |

```nix
services.agent-plugins.hookModes = {
  scratchpad-guard = "deny";
  reply-lint = "off";
};
```

A plugin enabled in managed settings can't be turned off in a session, so the mode is how a
misfiring hook is turned down: a change here and a switch, with no change to the hook.

A hook reads its mode through `lib/hook-mode.sh`, which `mkClaudePlugin` copies into every plugin
it builds. A bash hook sources it and calls `hook_mode <name>`; a hook in another language runs
`bash "${CLAUDE_PLUGIN_ROOT}/lib/hook-mode.sh" <name>`. Either prints the mode from the file in
`AGENT_HOOK_MODES`, and `remind` when the variable, the file or the name is missing, so a hook
nobody has set only reminds.

**A hook's first release is `remind`.** It moves to `deny` only by a change to `hookModes` the
user makes after a trial of a few days, and its plan node says what the trial must show. A hook
left at `remind` enforces nothing, so these, still at `remind`, are listed here until they move:

| Hook               | Plugin                      | Denies or blocks                                         |
| ------------------ | --------------------------- | -------------------------------------------------------- |
| `scratchpad-guard` | `coding-agent-skills-hooks` | a call that writes a scratchpad script, at PreToolUse    |
| `browser-check`    | `coding-agent-skills-hooks` | a Claude in Chrome call, wrong browser, at PreToolUse    |
| `reply-lint`       | `coding-agent-skills-hooks` | a final reply the reply lint fails, at Stop              |

These three still read their mode from a line in their skill's preferences file; reading it
through `hook_mode` instead is a change in `coding-agent-skills`, whose hooks plugin then needs
`mkClaudePlugin` from this flake to carry the helper.

## Library

- `lib.mkClaudePlugin pkgs { src, excludeSkills ? [ ], postPatch ? "" }`: copies a plugin directory
  into the store, removes the `skills/` directories named in `excludeSkills`, adds the hook-mode
  helper as `lib/hook-mode.sh` with a pinned `jq` (a plugin that already has that file fails the
  build), runs `postPatch`, and reads its name and version from `.claude-plugin/plugin.json`. The
  result is overridable with `.override`.
- `lib.mkMarketplace pkgs { name, owner, plugins }`: a local marketplace listing the plugins.
- `lib.mkSafetyNetHome pkgs rulebooks`: a CC Safety Net home folder for `CC_SAFETY_NET_HOME`.

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
  plugin from the generated marketplace, points `CC_SAFETY_NET_HOME` at the rulebooks, points
  `AGENT_HOOK_MODES` at `hook-modes.json` and merges `extraSettings`; disabled, it writes nothing.
- `hook-mode`: a test plugin's hook (`tests/fixtures/hook-mode-plugin`), run with the
  `AGENT_HOOK_MODES` the module writes, denies at `deny`, adds context at `remind` and is silent
  at `off`; with no `hookModes`, no file, or a name or value the file lacks, every hook reports
  `remind`; and every plugin `mkClaudePlugin` builds here carries the helper.
- `agent-plugins-cli`: the dev shell tool's unit tests of its argument parsing and the `nix`
  commands each token plans pass, its `--help` lists every token, and `update` rejects an input
  `flake.lock` lacks.
- `formatting`: fails if `nix fmt` (treefmt running nixfmt and ruff) would change a file.
