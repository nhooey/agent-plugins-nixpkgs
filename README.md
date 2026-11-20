# agent-plugins-nixpkgs

Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through Claude Code's managed settings.
The plugins' code changes only when this flake's lock does.
No Claude session or user setting can turn off a managed plugin; a user plugin is installed for you to enable, so `claude --plugin-dir` can override it.

Its sibling for skills is [`skillspkgs`](https://github.com/nhooey/skillspkgs).

## Packages

| Package                                | Plugin                                                                                                                                                                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cc-safety-net`                        | [CC Safety Net](https://github.com/kenryu42/cc-safety-net): blocks destructive shell commands and secret reads. Its hook runs with Nix's `node`.                                                                       |
| `superpowers`                          | [superpowers](https://github.com/obra/superpowers): brainstorming, planning, TDD, debugging and review workflows. Its SessionStart hook injects `using-superpowers`; set `SUPERPOWERS_DISABLE_TELEMETRY=1` to stop its logo fetch. |
| `trailofbits-insecure-defaults`        | [insecure-defaults](https://github.com/trailofbits/skills/tree/main/plugins/insecure-defaults): audits fail-open paths, fallback secrets, weak crypto and debug features.                                               |
| `trailofbits-sharp-edges`              | [sharp-edges](https://github.com/trailofbits/skills/tree/main/plugins/sharp-edges): reviews API misuse and footguns, with per-language references.                                                                      |
| `trailofbits-spec-to-code-compliance`  | [spec-to-code-compliance](https://github.com/trailofbits/skills/tree/main/plugins/spec-to-code-compliance): checks an implementation against its spec.                                                                  |

Vendored plugins come from `flake = false` inputs, so `flake.lock` pins them.
Update one with `agent-plugins update cc-safety-net-src` in the dev shell, or all of them with `agent-plugins update`.

To load a plugin without some of its skills, override it:

```nix
agent-plugins-nixpkgs.packages.${system}.superpowers.override {
  excludeSkills = [ "diagnosing-superpowers" ];
}
```

A name the plugin doesn't have under `skills/` fails the build, so an upstream rename can't bring a skill back unnoticed.

To load plugins for one session without installing them, pass each package's store path to `claude --plugin-dir`.

First-party plugin repositories should export their plugin directory as a flake package of their own; this flake then takes them as inputs and passes them through.
A repository that exports no package with the passthru `mkMarketplace` reads, such as `agentree-statusline`, is taken as a `flake = false` source instead, and its plugin directory is built here with `mkClaudePlugin`.
A program a hook calls that isn't in the plugin's folder and isn't certain to be on PATH is patched in from the same pin.
These come through so far: the two `*-hooks` plugins are hooks-only, their `hooks.json` running scripts copied in from the skills that document and test them, and the others have code of their own:

| Package                     | Plugin                                                                                                                                                                                                                                                                                                                  |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `coding-agent-skills-hooks` | The `hooks-plugin` package of [`coding-agent-skills`](https://github.com/nhooey/coding-agent-skills): `session-build-limits.sh` at SessionStart, the scratchpad guard before Bash, Write and Edit and at SubagentStart, the memory-write reminder, the plans check, the browser check, and the reply lint at Stop. |
| `git-skills-hooks`          | The `hooks-plugin` package of [`git-skills`](https://github.com/nhooey/git-skills): `pull-request-sync-check.sh` after Bash, which flags an open pull request whose title or body has drifted from its commit.                                                                                                       |
| `coding-agent-kanban-turns` | The `plugin` package of [`coding-agent-kanban-turns`](https://github.com/nhooey/coding-agent-kanban-turns): the kanban turn responses' mod, which draws clickable answers for Decide items and registers the `kanban_options` tool. |
| `agentree-statusline`       | The `plugin/` folder of [`agentree-statusline`](https://github.com/nhooey/agentree-statusline), built here with `mkClaudePlugin` from the `flake = false` input `agentree-statusline-src`: the mod that draws the session and its subagents as a live tree above the prompt, with cost, plan usage and timing. |
| `claffeinate`               | [`claffeinate`](https://github.com/nhooey/claffeinate), built from the input `claffeinate-src`: hooks that keep the Mac awake through `caffeinate` while a turn, subagent or background shell runs, its `claffeinate` command and its `set` and `status` skills; its hook and command run the pinned `jq`. |
| `terminal-width`            | [`claude-code-terminal-width`](https://github.com/nhooey/claude-code-terminal-width), built from the input `claude-code-terminal-width-src`: the mod that tells the model the terminal's width when it changes. |
| `nix-devshell-cached-exports` | [`nix-devshell-cached-exports`](https://github.com/nhooey/nix-devshell-cached-exports), built from the input `nix-devshell-cached-exports-src`: hooks that load the project's Nix devshell into every Bash command, and the `worktree-worker` agent; its hooks run the command its `package.nix` builds from the same pin. |

An update to any of them is a lock bump here (`agent-plugins update coding-agent-skills`, `agent-plugins update git-skills`, `agent-plugins update coding-agent-kanban-turns`, or `agent-plugins update` with the plugin's `*-src` input), then a lock bump of this flake in MyNixOS, and a switch.
Claude Code loads the new build at the next session start.

## nix-darwin module

```nix
{
  inputs.agent-plugins-nixpkgs.url = "github:nhooey/agent-plugins-nixpkgs";

  # In a nix-darwin configuration:
  imports = [ inputs.agent-plugins-nixpkgs.darwinModules.default ];
  services.agent-plugins = {
    enable = true;
    # Installed and enabled in the managed drop-in: no session can turn them off.
    managedPlugins = [ inputs.agent-plugins-nixpkgs.packages.aarch64-darwin.cc-safety-net ];
    # Installed only: enable them in your own settings, so `claude --plugin-dir` can override them.
    userPlugins = [ inputs.agent-plugins-nixpkgs.packages.aarch64-darwin.coding-agent-kanban-turns ];
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

On activation it writes `/Library/Application Support/ClaudeCode/managed-settings.d/<dropInName>`, owned by root, which:

- registers a marketplace, `<marketplaceName>`, built in the store from `managedPlugins` and `userPlugins` (`extraKnownMarketplaces`, `"source": "directory"`)
- enables each of `managedPlugins` as `<plugin>@<marketplaceName>` (`enabledPlugins`), but not `userPlugins`
- with rulebooks, sets `env.CC_SAFETY_NET_HOME` to a store folder holding them as real files, since Safety Net refuses symlinked config files, and `ccSafetyNet.transparentWrappers` as `rule.json`'s `transparent_wrappers`.
  Safety Net still writes its audit log to `~/.cc-safety-net/logs`.
- sets `env.AGENT_HOOK_MODES` to `hook-modes.json` in the store, written from `hookModes` ([Hook modes](#hook-modes)); with no `hookModes` it holds `{}`.
- merges in `extraSettings` last, so it can add any other managed setting or override these, except that its `enabledPlugins` can't set a user plugin.

A plugin you develop goes in `userPlugins`, and you enable it in your own settings, such as `~/.claude/settings.json`:

```json
{ "enabledPlugins": { "coding-agent-kanban-turns@nix-pinned": true } }
```

A managed `enabledPlugins` entry locks the plugin's name, so `claude --plugin-dir` can't load a working copy over it (Claude Code's [plugin name conflicts](https://code.claude.com/docs/en/plugins/loading.md)); a user setting gives way to it.
Evaluation fails an assertion naming the plugin when a plugin name is listed twice, in one list or across both, or when `extraSettings.enabledPlugins` sets a user plugin either way.
`managedPlugins` was called `plugins`, and that name still sets it, with a warning; set together, the two merge.

The options of `services.agent-plugins`:

| Option                            | Default                   | Meaning                                                                         |
| --------------------------------- | ------------------------- | ------------------------------------------------------------------------------- |
| `enable`                          | `false`                   | Write the drop-in on activation.                                                |
| `managedPlugins`                  | `[ ]`                     | Installed and enabled; no session can turn them off.                            |
| `userPlugins`                     | `[ ]`                     | Installed only; enable each in your own settings.                               |
| `ccSafetyNet.rulebooks`           | `[ ]`                     | CC Safety Net rulebooks, served read-only.                                      |
| `marketplaceName`                 | `"nix-pinned"`            | Name of the generated marketplace.                                              |
| `marketplaceOwner`                | `"nix"`                   | Owner name written into the marketplace manifest.                               |
| `ccSafetyNet.transparentWrappers` | `[ ]`                     | Commands, such as `"nix"`, whose wrapped commands the rulebooks' rules apply to. |
| `hookModes`                       | `{ }`                     | Each hook's mode by name: `off`, `remind` or `deny`.                            |
| `extraSettings`                   | `{ }`                     | More managed settings merged into the drop-in.                                  |
| `dropInName`                      | `"40-agent-plugins.json"` | File name of the drop-in under `managed-settings.d`.                            |

Rulebooks published by first-party skill repositories are flake outputs under `safetyNetRulebooks`, ready for `ccSafetyNet.rulebooks`:

```nix
ccSafetyNet.rulebooks = [
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.git-avoid-sweeping-operations
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.git-avoid-sweeping-operations-with-exclusions
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.shell-hygiene
  inputs.agent-plugins-nixpkgs.safetyNetRulebooks.shell-hygiene-secrets
];
ccSafetyNet.transparentWrappers = [ "nix" ];
```

- `git-avoid-sweeping-operations` comes from [`git-skills`](https://github.com/nhooey/git-skills).
- `git-avoid-sweeping-operations-with-exclusions` comes from `git-skills` too: it blocks a bare `git stash` and `git config --global` or `--system` writes, rules whose safe forms are carved out with `exclude_args`, so they sit in a rulebook of their own.
- `shell-hygiene` comes from [`shell-skills`](https://github.com/nhooey/shell-skills): it blocks killing processes by pattern, `rsync --delete`, recursive `chmod` and `chown`, machine-wide installs, prunes, service and settings changes, common numeric `chmod` modes, and commands that print a secret, such as `op read` and `gh auth token`.
- `shell-hygiene-secrets`, also from `shell-skills`, holds the secret rules that need a command path, such as `op item get --format json`, and is exported once the pinned `shell-skills-src` has it.

With `"nix"` as a transparent wrapper, these rules also block their commands run through `nix develop --command` or `nix shell`; the checks run the rulebooks' fixtures that way.

Nix doesn't track the drop-in: disabling the module leaves it in place, so delete it with `sudo` afterwards.

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

A plugin enabled in managed settings can't be turned off in a session, so the mode is how a misfiring hook is turned down: a change here and a switch, with no change to the hook.

A hook reads its mode through `lib/hook-mode.sh`, which `mkClaudePlugin` copies into every plugin it builds.
A bash hook sources it and calls `hook_mode <name>`; a hook in another language runs `bash "${CLAUDE_PLUGIN_ROOT}/lib/hook-mode.sh" <name>`.
Either prints the mode from the file in `AGENT_HOOK_MODES`, and `remind` when the variable, the file or the name is missing, so a hook nobody has set only reminds.

**A hook's first release is `remind`.**
It moves to `deny` only by a change to `hookModes` the user makes after a trial of a few days, and its plan node says what the trial must show.
A hook left at `remind` enforces nothing, so these, still at `remind`, are listed here until they move:

| Hook               | Plugin                      | Denies or blocks                                         |
| ------------------ | --------------------------- | -------------------------------------------------------- |
| `scratchpad-guard` | `coding-agent-skills-hooks` | a call that writes a scratchpad script, at PreToolUse    |
| `browser-check`    | `coding-agent-skills-hooks` | a Claude in Chrome call, wrong browser, at PreToolUse    |
| `reply-lint`       | `coding-agent-skills-hooks` | a final reply the reply lint fails, at Stop              |

These three still read their mode from a line in their skill's preferences file; reading it through `hook_mode` instead is a change in `coding-agent-skills`, whose hooks plugin then needs `mkClaudePlugin` from this flake to carry the helper.

## Library

- `lib.mkClaudePlugin pkgs { src, include ? null, excludeSkills ? [ ], postPatch ? "" }`: copies a plugin directory into the store, removes the `skills/` directories named in `excludeSkills`, adds the hook-mode helper as `lib/hook-mode.sh` with a pinned `jq` (a plugin that already has that file fails the build), runs `postPatch`, and reads its name and version from `.claude-plugin/plugin.json`.
  The result is overridable with `.override`.
  With `include`, a list of paths relative to `src`, only those are copied, through `lib.fileset`, and any that don't exist are skipped, so a plugin's repository can leave its tests, docs and flake out of the build; `src` must then be a path, such as `./.`.
  Without it, all of `src` is copied.
- `flakeModules.claudePlugin`: a [flake-parts](https://flake.parts/) module for a plugin's own repository.
  Its `perSystem` option `agent-plugins.claudePlugin` builds the plugin with `mkClaudePlugin` as `packages.<packageName>`, ready for `services.agent-plugins.userPlugins` or `managedPlugins`.
  When the flake also imports numtide devshell's flake module, it adds a `plugin-build` command to `devshells.default`, which runs `nix build "$PRJ_ROOT#<packageName>" --out-link "$PRJ_ROOT/result-plugin"`; without devshell, nothing is added.

  | Option        | Default                                                                  | Meaning                                         |
  | ------------- | ------------------------------------------------------------------------ | ----------------------------------------------- |
  | `enable`      | `false`                                                                  | Build the plugin.                               |
  | `src`         | —                                                                        | The plugin's root, as a path such as `./.`.     |
  | `include`     | `[ ".claude-plugin/plugin.json" "defaults" "hooks" "src" "types" ]`      | Paths under `src` to copy; missing are skipped. |
  | `postPatch`   | `""`                                                                     | Shell run in the copy, as `mkClaudePlugin`'s.   |
  | `packageName` | `"plugin"`                                                               | The package's name.                             |

  ```nix
  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.agent-plugins-nixpkgs.flakeModules.claudePlugin
        inputs.devshell.flakeModule
      ];
      systems = import inputs.systems;
      perSystem.agent-plugins.claudePlugin = {
        enable = true;
        src = ./.;
      };
    };
  ```
- `lib.mkMarketplace pkgs { name, owner, plugins }`: a local marketplace listing the plugins.
- `lib.mkSafetyNetHome pkgs rulebooks`, or `lib.mkSafetyNetHome pkgs { rulebooks, transparentWrappers ? [ ] }`: a CC Safety Net home folder for `CC_SAFETY_NET_HOME`.

## Dev shell

`nix develop` enters a [numtide devshell](https://github.com/numtide/devshell) and installs the agent skills in `.agents/skills/`; `menu` lists its commands.
Its tool, `agent-plugins`, takes the command tokens `build`, `check`, `fmt`, `list`, `update` and `skills`, each with `--help`, and `--dry-run` prints the `nix` commands a token runs without running them.

## Checks

`agent-plugins check`, or `nix flake check`, runs the checks in `tests/`, one file per concern, with shared shell in `tests/lib/helpers.sh`:

- `vendored-plugins`: each plugin's name, version and derivation name come from its manifest, Safety Net's hook runs the pinned node, and `excludeSkills` removes exactly the skill it names.
- `first-party-plugins`: each passed-through hooks plugin is named by its manifest, and holds every script its `hooks.json` runs; `agentree-statusline`, `claffeinate`, `terminal-width` and `nix-devshell-cached-exports` are named by their manifests, hold only the paths their `include` lists, and hold every module their `hooks.json` registers and every script it runs; `claffeinate`'s scripts put the pinned `jq` on their PATH, and `nix-devshell-cached-exports`' hooks run the pinned command with none on PATH.
- `exclude-skills-unknown-name`: naming a skill the plugin lacks fails the build.
- `mk-claude-plugin-include`: `include` copies only the paths it lists, skips those the plugin lacks, and still adds the hook-mode helper; without it, the whole source is copied.
- `claude-plugin-flake-module`: `flakeModules.claudePlugin`, in minimal flake-parts consumers, builds `packages.plugin` with the default `include`, puts a file `postPatch` writes in the package, adds the `plugin-build` command only when devshell's flake module is imported, and adds nothing when disabled.
- `marketplace`: `mkMarketplace` lists each plugin's name, source and version, and links each to its build.
- `safety-net-home`: `mkSafetyNetHome` writes `rule.json`, with any transparent wrappers, and each rulebook as a regular file.
- `cc-safety-net-hook`: the hook, run the way Claude Code runs it, denies a rule from `safetyNetRulebooks.git-avoid-sweeping-operations`, one from `git-avoid-sweeping-operations-with-exclusions`, rules from rulebooks written in the check, and a built-in rule, each by name; denies `nix develop --command op item get X --format json` with `nix` as a transparent wrapper; and allows `git status` and `op item list --format json`.
- `safety-net-rulebooks`: each rulebook in `safetyNetRulebooks`, `git-avoid-sweeping-operations`, `git-avoid-sweeping-operations-with-exclusions` and `shell-hygiene`, passes its own `tests` fixtures through the hook, with `nix` as a transparent wrapper: a `blocked` fixture is denied by its own rule, an `allowed` one isn't denied, and every rule has a `blocked` fixture.
- `darwin-module`: the nix-darwin module, evaluated on its own, writes a drop-in whose generated marketplace lists `managedPlugins` and `userPlugins` and which enables only `managedPlugins`, points `CC_SAFETY_NET_HOME` at the rulebooks and the transparent wrappers, points `AGENT_HOOK_MODES` at `hook-modes.json` and merges `extraSettings`; disabled, it writes nothing.
  The old `plugins` name still sets `managedPlugins`, with a warning, and merges with it; with only `userPlugins`, nothing is enabled and the marketplace is still registered.
  A plugin name listed twice, in one list or across both, fails an assertion, and so does a user plugin set in `extraSettings.enabledPlugins`.
- `hook-mode`: a test plugin's hook (`tests/fixtures/hook-mode-plugin`), run with the `AGENT_HOOK_MODES` the module writes, denies at `deny`, adds context at `remind` and is silent at `off`; with no `hookModes`, no file, or a name or value the file lacks, every hook reports `remind`; and every plugin `mkClaudePlugin` builds here carries the helper.
- `agent-plugins-cli`: the dev shell tool's unit tests of its argument parsing and the `nix` commands each token plans pass, its `--help` lists every token, and `update` rejects an input `flake.lock` lacks.
- `formatting`: fails if `nix fmt` (treefmt running nixfmt and ruff) would change a file.
