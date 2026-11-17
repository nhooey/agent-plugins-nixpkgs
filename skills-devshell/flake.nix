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

    # skillspkgs' per-family combinations. This repository is in the skill
    # packaging family, so it takes `skill-packaging` whole and adds nothing:
    # it uses no language or tool the rest of that family doesn't.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
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
        { source = inputs.skillspkgs-combinations.combinations.skill-packaging; }
      ];
    };
}
