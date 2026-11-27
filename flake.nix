{
  description = "agent-plugins-nixpkgs: Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through managed settings";

  # Two kinds of plugin packages, as in skillspkgs:
  # 1. VENDORED third-party plugins: upstream ships no Nix package, so pkgs/ builds them from the
  #    `flake = false` *-src inputs below.
  # 2. FIRST-PARTY plugins: a repository that exports its plugin as a flake package of its own
  #    is taken as an input and passed through: coding-agent-skills and git-skills, each as its
  #    `hooks-plugin` package, and coding-agent-kanban-turns as its `plugin` package.
  #    agentree-statusline, claffeinate, terminal-width and nix-devshell-cached-exports are the
  #    exception: their flakes export no plugin package with the passthru the module reads, so
  #    pkgs/ builds them from `flake = false` *-src inputs, as it does the vendored plugins.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Only for the checks that evaluate flakeModules.claudePlugin in a consumer flake.
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
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
    # ---- first-party plugin repositories ----
    # On their default branches. Flakes for their `hooks-plugin` or `plugin` packages (packages
    # below), except the *-src ones, plain sources pkgs/ builds with mkClaudePlugin.
    # git-skills' rulebook still comes from git-skills-src below, at its own pin.
    coding-agent-skills = {
      url = "github:nhooey/coding-agent-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-skills = {
      url = "github:nhooey/git-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The kanban turn responses' mod, as its `plugin` package, which it builds with this flake's
    # flakeModules.claudePlugin. Its agent-plugins-nixpkgs input follows this flake (`""`), so
    # the lock doesn't hold another copy of this repository, with all its inputs, inside it.
    coding-agent-kanban-turns = {
      url = "github:nhooey/coding-agent-kanban-turns";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
        agent-plugins-nixpkgs.follows = "";
      };
    };
    # The agent tree status line's mod, built in pkgs/ from its plugin/ folder with
    # lib.mkClaudePlugin, for the passthru the module reads. A plain source: its flake's
    # dev-shell inputs aren't needed here.
    agentree-statusline-src = {
      url = "github:nhooey/agentree-statusline";
      flake = false;
    };
    # Plugins whose repository root is the plugin, built in pkgs/ like agentree-statusline.
    claffeinate-src = {
      url = "github:nhooey/claffeinate";
      flake = false;
    };
    claude-code-terminal-width-src = {
      url = "github:nhooey/claude-code-terminal-width";
      flake = false;
    };
    nix-devshell-cached-exports-src = {
      url = "github:nhooey/nix-devshell-cached-exports";
      flake = false;
    };

    # CC Safety Net rulebooks published in first-party skill repos (safetyNetRulebooks below).
    # Taken as plain sources: only the rulebook files are read, not the repos' flakes.
    git-skills-src = {
      url = "github:nhooey/git-skills";
      flake = false;
    };
    # Each on the repository's default branch.
    shell-skills-src = {
      url = "github:nhooey/shell-skills";
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
      # The `agent-plugins` command-line tool, kept out of `packages`, which lists plugins and
      # git-skills' git hooks folder.
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
      # shell-hygiene-secrets is exported once the pinned shell-skills-src has it.
      safetyNetRulebooks =
        let
          path = src: name: "${src}/.cc-safety-net/rules/${name}/rulebook.json";
          rulebook = src: name: nixpkgs.lib.importJSON (path src name);
        in
        {
          git-avoid-sweeping-operations = rulebook inputs.git-skills-src "git-avoid-sweeping-operations";
          git-avoid-sweeping-operations-with-exclusions = rulebook inputs.git-skills-src "git-avoid-sweeping-operations-with-exclusions";
          shell-hygiene = rulebook inputs.shell-skills-src "shell-hygiene";
        }
        //
          nixpkgs.lib.optionalAttrs
            (builtins.pathExists (path inputs.shell-skills-src "shell-hygiene-secrets"))
            {
              shell-hygiene-secrets = rulebook inputs.shell-skills-src "shell-hygiene-secrets";
            };

      darwinModules.default = import ./modules/darwin.nix { inherit self; };

      # For a plugin's own repository: builds its plugin folder as packages.plugin, and adds a
      # `plugin-build` devshell command when numtide devshell's flake module is imported too.
      flakeModules.claudePlugin = import ./modules/claude-plugin.nix { inherit self; };

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
