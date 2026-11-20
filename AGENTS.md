# agent-plugins-nixpkgs

Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through Claude Code's managed settings.
[README.md](README.md) describes the packages, the module and the library.

- `pkgs/` builds the vendored third-party plugins from the `flake = false` `*-src` inputs.
- `lib/` holds `mkClaudePlugin`, `mkMarketplace` and `mkSafetyNetHome`.
- `modules/darwin.nix` is the nix-darwin module; `modules/claude-plugin.nix` is `flakeModules.claudePlugin`, the flake-parts module a plugin's own repository imports.
- `skills-devshell/` is the sub-flake whose skills `nix develop` installs in `.agents/skills/`: skillspkgs' `skill-packaging` combination, with no additions.
- `devshell.nix` is the dev shell; `scripts/agent_plugins.py` is its `agent-plugins` tool.

## Managed and user plugins

A plugin someone develops goes in `userPlugins`, never `managedPlugins`: a managed
`enabledPlugins` entry locks its name, so `claude --plugin-dir` can't load a working copy over it.
The README's [nix-darwin module](README.md#nix-darwin-module) section has the options and an example.

## Build and test

`nix develop` enters the dev shell and installs the agent skills; `menu` lists its commands.
Each `agent-plugins` command token prints the `nix` commands it runs, and `--dry-run` only prints them:

```bash
agent-plugins build cc-safety-net      # or any other package; --all builds every one
agent-plugins check                    # nix flake check; name checks to run only those
agent-plugins fmt                      # formats the Nix and Python files through treefmt
agent-plugins update cc-safety-net-src # bumps one input; no name bumps every *-src input
agent-plugins list                     # the plugin packages
```
