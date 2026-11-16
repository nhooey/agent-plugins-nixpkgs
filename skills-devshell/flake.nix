{
  description = "agent-plugins-nixpkgs dev-shell skill set — an isolated sub-flake invoked at RUNTIME by the root devShell, never a root input, so the skill sources live only in THIS flake's lock.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    # The builder lib; it carries no skill inputs.
    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Skill sources, the same repos `github:nhooey/skillspkgs` aggregates.
    # They follow `nixpkgs` but not `agent-skill-flake`, so each keeps its own
    # compatible builder.
    coding-agent-skills = {
      url = "github:nhooey/coding-agent-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-skills = {
      url = "github:nhooey/git-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-skills = {
      url = "github:nhooey/nix-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    shell-skills = {
      url = "github:nhooey/shell-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    writing-skills = {
      url = "github:nhooey/writing-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      agent-skill-flake,
      ...
    }@inputs:
    agent-skill-flake.lib.mkDevshellSkillsFlake {
      inherit nixpkgs;
      systems = import inputs.systems;
      name = "agent-plugins-nixpkgs-devshell";
      sources = [
        # Commits, branches and pull requests.
        { source = inputs.git-skills; }
        # Writing this flake, its plugin packages and its nix-darwin module,
        # and bumping the vendored plugin sources.
        {
          source = inputs.nix-skills;
          skills = [
            "nix-flakes"
            "nix-flake-recursive-bump-input-versions"
          ];
        }
        # Safe shell commands: named deletes, PIDs, no machine-wide changes.
        { source = inputs.shell-skills; }
        # Headless runs in checkouts, a tidy scratchpad, the plans graph, and
        # the turn-response shape the user's own instructions ask for.
        {
          source = inputs.coding-agent-skills;
          skills = [
            "coding-agent-headless-in-checkout"
            "coding-agent-kanban-turn-responses"
            "coding-agent-plans-as-graph"
            "coding-agent-scratchpad-scripts"
          ];
        }
        # Commit messages, the README and AGENTS.md.
        { source = inputs.writing-skills; }
      ];
    };
}
