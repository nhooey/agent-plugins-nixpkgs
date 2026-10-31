{
  description = "agent-plugins-nixpkgs: Claude Code plugins packaged with Nix, and a nix-darwin module that installs them through managed settings";

  # Two kinds of plugin packages, as in skillspkgs:
  # 1. VENDORED third-party plugins: upstream ships no Nix package, so pkgs/ builds them from the
  #    `flake = false` *-src inputs below.
  # 2. FIRST-PARTY plugins: repositories that export their plugin as a flake package of their
  #    own are taken as inputs and passed through (none yet).
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
    { self, nixpkgs, ... }@inputs:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
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

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      checks = forAllSystems (
        pkgs:
        let
          plugin = self.packages.${pkgs.stdenv.hostPlatform.system}.cc-safety-net;
          marketplace = self.lib.mkMarketplace pkgs {
            name = "check";
            owner = "check";
            plugins = [ plugin ];
          };
          home = self.lib.mkSafetyNetHome pkgs [
            self.safetyNetRulebooks.git-avoid-sweeping-operations
            {
              rulebook_version = 1;
              name = "check-rules";
              version = "1.0.0";
              allowed_commands = [ "git" ];
              rules = [
                {
                  name = "block-git-add-all";
                  command = "git";
                  subcommand = "add";
                  block_args = [ "-A" ];
                  reason = "check";
                }
              ];
            }
          ];
        in
        {
          # Every vendored plugin has a manifest, and excludeSkills removes exactly what it names.
          vendored-plugins =
            let
              p = self.packages.${pkgs.stdenv.hostPlatform.system};
              trimmed = p.superpowers.override { excludeSkills = [ "diagnosing-superpowers" ]; };
            in
            pkgs.runCommand "check-vendored-plugins" { } ''
              for plugin in ${p.superpowers} ${p.trailofbits-insecure-defaults} \
                  ${p.trailofbits-sharp-edges} ${p.trailofbits-spec-to-code-compliance}; do
                test -f $plugin/.claude-plugin/plugin.json
              done
              test -d ${p.superpowers}/skills/diagnosing-superpowers
              ! test -e ${trimmed}/skills/diagnosing-superpowers
              test -f ${trimmed}/skills/brainstorming/SKILL.md
              touch $out
            '';

          # The hook, run as Claude Code runs it, blocks rules from both rulebooks and a built-in
          # rule from the read-only home, and lets a harmless command through.
          cc-safety-net-hook =
            pkgs.runCommand "check-cc-safety-net-hook" { nativeBuildInputs = [ pkgs.jq ]; }
              ''
                    export HOME=$TMPDIR CC_SAFETY_NET_HOME=${home}
                    test -f ${marketplace}/.claude-plugin/marketplace.json
                    test -e ${marketplace}/cc-safety-net/.claude-plugin/plugin.json
                    hook=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' ${plugin}/hooks/hooks.json \
                      | sed "s|\''${CLAUDE_PLUGIN_ROOT}|${plugin}|")
                    run() {
                      jq -nc --arg c "$1" '{session_id:"check",transcript_path:"/tmp/check.jsonl",
                        hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},
                        cwd:"/tmp",permission_mode:"default"}' | eval "$hook"
                    }
                    run 'git add -A' | grep -q 'custom.git-avoid-sweeping-operations/add-sweep'
                run 'git -C repo add -A' | grep -q 'custom.check-rules/block-git-add-all'
                    run 'git reset --hard' | grep -q 'git.reset-hard'
                    run 'git stash' | grep -q 'custom.git-avoid-sweeping-operations/stash-sweep'
                    ! run 'git status' | grep -q deny
                    touch $out
              '';
        }
      );
    };
}
