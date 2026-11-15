# agent-plugins-nixpkgs

Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through Claude
Code's managed settings. [README.md](README.md) describes the packages, the module and the library.

- `pkgs/` builds the vendored third-party plugins from the `flake = false` `*-src` inputs.
- `lib/` holds `mkClaudePlugin`, `mkMarketplace` and `mkSafetyNetHome`.
- `modules/darwin.nix` is the nix-darwin module.
- `skills-devshell/` is the sub-flake whose skills `nix develop` installs in `.agents/skills/`.

## Build and test

```bash
nix develop                          # installs the agent skills
nix build .#cc-safety-net            # or any other package
nix flake check                      # builds the plugins, runs the Safety Net hook checks, checks formatting
nix fmt                              # formats the Nix files with nixfmt, through treefmt
nix flake update cc-safety-net-src   # bumps one vendored plugin
```
