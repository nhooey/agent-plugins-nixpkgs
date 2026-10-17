# agent-plugins-nixpkgs

Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through
Claude Code's managed settings. The plugins' code changes only when this flake's lock does, and
no Claude session or user setting can turn them off.

Its sibling for skills is [`skillspkgs`](https://github.com/nhooey/skillspkgs).

## Packages

| Package         | Plugin                                                                                                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `cc-safety-net` | [CC Safety Net](https://github.com/kenryu42/cc-safety-net): blocks destructive shell commands and secret reads. Its hook runs with Nix's `node`. |

Vendored plugins come from `flake = false` inputs, so `flake.lock` pins them. Update one with:

```bash
nix flake update cc-safety-net-src
```

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

On activation it writes `/Library/Application Support/ClaudeCode/managed-settings.d/40-agent-plugins.json`,
owned by root, which:

- registers a marketplace, `nix-pinned`, built in the store from the listed plugins
  (`extraKnownMarketplaces`, `"source": "directory"`)
- enables each plugin as `<plugin>@nix-pinned` (`enabledPlugins`)
- with rulebooks, sets `env.CC_SAFETY_NET_HOME` to a store folder holding them as real files,
  since Safety Net refuses symlinked config files. Safety Net still writes its audit log to
  `~/.cc-safety-net/logs`.

Nix doesn't track the drop-in: disabling the module leaves it in place, so delete it with `sudo`
afterwards.

## Library

- `lib.mkClaudePlugin pkgs { src, postPatch ? "" }`: copies a plugin directory into the store and
  reads its name and version from `.claude-plugin/plugin.json`.
- `lib.mkMarketplace pkgs { name, owner, plugins }`: a local marketplace listing the plugins.
- `lib.mkSafetyNetHome pkgs rulebooks`: a CC Safety Net home folder for `CC_SAFETY_NET_HOME`.

## Checks

`nix flake check` builds the Safety Net package and a marketplace, then runs the plugin's hook the
way Claude Code does: it must block a rulebook rule and a built-in rule, and allow `git status`.
