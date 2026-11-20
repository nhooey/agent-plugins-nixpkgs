# flakeModules.claudePlugin, imported by minimal flake-parts consumers: without devshell it
# builds the plugin as packages.plugin with the five default paths; with numtide devshell's
# flake module it also adds a `plugin-build` command for the package; `postPatch` runs in the
# copy, so a file it writes lands in the package; disabled, it adds nothing.
{
  self,
  pkgs,
  helpers,
}:
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (self.inputs) nixpkgs;
  src = ./fixtures/hook-mode-plugin;
  consumer =
    imports: claudePlugin:
    self.inputs.flake-parts.lib.mkFlake
      {
        inputs = {
          # flake-parts reads self.inputs for inputs'.
          self = {
            outPath = src;
            inputs = { inherit nixpkgs; };
          };
          inherit nixpkgs;
        };
      }
      {
        systems = [ system ];
        debug = true;
        imports = [ self.flakeModules.claudePlugin ] ++ imports;
        perSystem.agent-plugins.claudePlugin = claudePlugin;
      };
  plain = consumer [ ] {
    enable = true;
    inherit src;
  };
  withDevshell = consumer [ self.inputs.devshell.flakeModule ] {
    enable = true;
    inherit src;
    packageName = "my-plugin";
  };
  withPostPatch = consumer [ ] {
    enable = true;
    inherit src;
    postPatch = ''
      mkdir -p vendor
      echo generated > vendor/generated.js
    '';
  };
  disabled = consumer [ ] { inherit src; };
  expected = self.lib.mkClaudePlugin pkgs {
    inherit src;
    include = [
      ".claude-plugin/plugin.json"
      "defaults"
      "hooks"
      "src"
      "types"
    ];
  };
  facts = pkgs.writeText "facts.json" (
    builtins.toJSON {
      plainPackages = builtins.attrNames (plain.packages.${system} or { });
      plainHasDevshells = plain.allSystems.${system}.options ? devshells;
      plainMatches = plain.packages.${system}.plugin.drvPath == expected.drvPath;
      devshellPackages = builtins.attrNames withDevshell.packages.${system};
      commands = map (c: {
        inherit (c) name category command;
      }) withDevshell.allSystems.${system}.devshells.default.commands;
      devShell = withDevshell.devShells.${system} ? default;
      disabledPackages = builtins.attrNames (disabled.packages.${system} or { });
    }
  );
in
pkgs.runCommand "check-claude-plugin-flake-module" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}
  f=${facts}

  assert_json $f '.plainPackages == ["plugin"]' "without devshell, packages is plugin alone"
  assert_json $f '.plainHasDevshells == false' "without devshell, no devshells option"
  assert_json $f '.plainMatches' "packages.plugin is mkClaudePlugin with the default include"
  assert_missing ${plain.packages.${system}.plugin}/scripts "unlisted scripts/ in packages.plugin"

  assert_json $f '.devshellPackages == ["my-plugin"]' "packageName names the package"
  assert_json $f '.devShell' "devshell's flake module still makes devShells.default"
  assert_json $f \
    '[.commands[] | select(.name == "plugin-build")] == [{name: "plugin-build", category: "build", command: "nix build \"$PRJ_ROOT#my-plugin\" --out-link \"$PRJ_ROOT/result-plugin\""}]' \
    "plugin-build command"

  postPatched=${withPostPatch.packages.${system}.plugin}
  test "$(cat $postPatched/vendor/generated.js)" = generated \
    || fail "postPatch's vendor/generated.js missing from packages.plugin"
  test -e $postPatched/lib/hook-mode.sh || fail "hook-mode helper missing beside postPatch's file"

  assert_json $f '.disabledPackages == []' "disabled, no package"

  touch $out
''
