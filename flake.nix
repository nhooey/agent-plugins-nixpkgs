{
  description = "agent-plugins-nixpkgs: Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through managed settings";

  # Two kinds of plugin packages, as in skillspkgs:
  # 1. VENDORED third-party plugins: upstream ships no Nix package, so pkgs/ builds them from the
  #    `flake = false` *-src inputs below.
  # 2. FIRST-PARTY plugins: a repository that exports its plugin as a flake package of its own
  #    is taken as an input and passed through. No input is of this kind.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ---- vendored third-party sources ----
    # No rev in the URL: flake.lock pins it. Update with `nix flake update cc-safety-net-src`.
    cc-safety-net-src = {
      url = "github:kenryu42/cc-safety-net/plugin";
      flake = false;
    };
    superpowers-src = {
      url = "github:obra/superpowers";
      flake = false;
    };
    trailofbits-skills-src = {
      url = "github:trailofbits/skills";
      flake = false;
    };
    # CC Safety Net rulebooks published in first-party skill repos (safetyNetRulebooks below).
    # Taken as plain sources: only the rulebook files are read, not the repos' flakes.
    git-skills-src = {
      url = "github:nhooey/git-skills";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      devshell,
      treefmt-nix,
      ...
    }@inputs:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      treefmt = forAllSystems (
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.ruff-format.enable = true;
        }
      );
      # The `agent-plugins` command-line tool, kept out of `packages`, which lists plugins only.
      agentPluginsTool = pkgs: pkgs.callPackage ./scripts/agent-plugins.nix { };
    in
    {
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = forAllSystems (
        pkgs:
        import ./pkgs {
          inherit pkgs inputs;
          pluginLib = self.lib;
        }
      );

      # CC Safety Net rulebooks as attribute sets, for services.agent-plugins.ccSafetyNet.rulebooks.
      safetyNetRulebooks.git-avoid-sweeping-operations = nixpkgs.lib.importJSON "${inputs.git-skills-src}/.cc-safety-net/rules/git-avoid-sweeping-operations/rulebook.json";

      darwinModules.default = import ./modules/darwin.nix { inherit self; };

      formatter = forAllSystems (pkgs: treefmt.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);

      # The dev shell: `menu` lists its commands, and entering it installs the agent skills
      # (see devshell.nix).
      devShells = forAllSystems (pkgs: {
        default = import ./devshell.nix {
          inherit pkgs;
          mkShell = devshell.legacyPackages.${pkgs.stdenv.hostPlatform.system}.mkShell;
          agent-plugins = agentPluginsTool pkgs;
        };
      });

      # Behaviour checks live in tests/, one file per concern; formatting is checked here.
      checks = forAllSystems (
        pkgs:
        import ./tests {
          inherit self pkgs;
          agent-plugins = agentPluginsTool pkgs;
        }
        // {
          # `nix fmt` would change no file.
          formatting = treefmt.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
        }
      );
    };
}
