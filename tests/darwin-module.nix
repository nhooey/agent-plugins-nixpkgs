# The nix-darwin module, evaluated with the nix-darwin options it sets declared here, writes a
# drop-in that installs the marketplace, enables each plugin but the unmanaged ones, points
# Safety Net at the rulebooks and merges extraSettings; disabled, it writes nothing. An
# unmanaged name that matches no plugin fails an assertion.
{
  self,
  pkgs,
  helpers,
}:
let
  inherit (pkgs) lib;
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  evalConfig =
    cfg:
    (lib.evalModules {
      modules = [
        self.darwinModules.default
        {
          options.system.activationScripts.postActivation.text = lib.mkOption {
            type = lib.types.lines;
            default = "";
          };
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.unspecified;
            default = [ ];
          };
          config = {
            _module.args.pkgs = pkgs;
            services.agent-plugins = cfg;
          };
        }
      ];
    }).config;
  activationText = cfg: (evalConfig cfg).system.activationScripts.postActivation.text;
  # The messages of the assertions that fail, which nix-darwin stops the build with.
  failedAssertions =
    cfg: map (a: a.message) (lib.filter (a: !a.assertion) (evalConfig cfg).assertions);
  enabled = pkgs.writeText "activation-enabled" (activationText {
    enable = true;
    plugins = [
      p.cc-safety-net
      p.superpowers
    ];
    marketplaceName = "check-market";
    marketplaceOwner = "check-owner";
    dropInName = "50-check.json";
    ccSafetyNet.rulebooks = [ self.safetyNetRulebooks.git-avoid-sweeping-operations ];
    extraSettings = {
      env.CHECK_VAR = "1";
      permissions.deny = [ "Bash(rm -rf /)" ];
    };
  });
  noRulebooks = pkgs.writeText "activation-no-rulebooks" (activationText {
    enable = true;
    plugins = [ p.superpowers ];
  });
  unmanaged = {
    enable = true;
    plugins = [
      p.cc-safety-net
      p.superpowers
    ];
    unmanaged = [ "superpowers" ];
  };
  unmanagedActivation = pkgs.writeText "activation-unmanaged" (activationText unmanaged);
  # extraSettings can't bring an unmanaged plugin back, under any marketplace, value or case.
  unmanagedExtraActivation = pkgs.writeText "activation-unmanaged-extra" (
    activationText (
      unmanaged
      // {
        extraSettings.enabledPlugins = {
          "superpowers@nix-pinned" = true;
          "superpowers@elsewhere" = false;
          "SuperPowers@elsewhere" = true;
          "kept@elsewhere" = true;
        };
      }
    )
  );
  badName = failedAssertions (unmanaged // { unmanaged = [ "superpower" ]; });
  disabled = activationText {
    enable = false;
    plugins = [ p.superpowers ];
  };
  dropIns = "/Library/Application Support/ClaudeCode/managed-settings.d";
in
assert lib.assertMsg (disabled == "") "the disabled module still writes an activation script";
assert lib.assertMsg (
  failedAssertions unmanaged == [ ]
) "an unmanaged name that matches a plugin fails an assertion";
assert lib.assertMsg (
  lib.length badName == 1 && lib.hasInfix ''"superpower"'' (lib.head badName)
) "an unmanaged name that matches no plugin gives the failed assertions ${builtins.toJSON badName}";
pkgs.runCommand "check-darwin-module" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}

  # settings_of ACTIVATION DROP-IN: the settings file ACTIVATION installs as DROP-IN.
  settings_of() {
    line=$(grep -F '"${dropIns}/'"$2"'"' "$1") || fail "$1 doesn't install ${dropIns}/$2: $(cat "$1")"
    echo "$line" | grep -o '/nix/store/[^ ]*-claude-agent-plugins.json'
  }

  s=$(settings_of ${enabled} 50-check.json)
  assert_json $s '.enabledPlugins == {"cc-safety-net@check-market": true, "superpowers@check-market": true}' "enabledPlugins"
  assert_json $s '.extraKnownMarketplaces | keys == ["check-market"]' "one known marketplace"
  assert_json $s '.extraKnownMarketplaces["check-market"].source.source == "directory"' "marketplace source kind"
  market=$(jq -r '.extraKnownMarketplaces["check-market"].source.path' $s)
  assert_json $market/.claude-plugin/marketplace.json \
    '.name == "check-market" and .owner.name == "check-owner" and ([.plugins[].name] == ["cc-safety-net", "superpowers"])' \
    "the marketplace the drop-in points at"
  home=$(jq -r '.env.CC_SAFETY_NET_HOME' $s)
  assert_json $home/rules/rule.json '.rules == ["git-avoid-sweeping-operations"]' "CC_SAFETY_NET_HOME rulebooks"
  assert_json $s '.env.CHECK_VAR == "1"' "extraSettings env merged beside CC_SAFETY_NET_HOME"
  assert_json $s '.permissions.deny == ["Bash(rm -rf /)"]' "extraSettings permissions"

  s=$(settings_of ${noRulebooks} 40-agent-plugins.json)
  assert_json $s '.enabledPlugins == {"superpowers@nix-pinned": true}' "default marketplace name"
  assert_json $s '.env == {}' "no CC_SAFETY_NET_HOME without rulebooks"
  assert_json "$(jq -r '.extraKnownMarketplaces["nix-pinned"].source.path' $s)/.claude-plugin/marketplace.json" \
    '.owner.name == "nix"' "default marketplace owner"

  s=$(settings_of ${unmanagedActivation} 40-agent-plugins.json)
  assert_json $s '.enabledPlugins == {"cc-safety-net@nix-pinned": true}' "an unmanaged plugin left out of enabledPlugins"
  assert_json "$(jq -r '.extraKnownMarketplaces["nix-pinned"].source.path' $s)/.claude-plugin/marketplace.json" \
    '[.plugins[].name] == ["cc-safety-net", "superpowers"]' "an unmanaged plugin kept in the marketplace"

  s=$(settings_of ${unmanagedExtraActivation} 40-agent-plugins.json)
  assert_json $s '.enabledPlugins == {"cc-safety-net@nix-pinned": true, "kept@elsewhere": true}' \
    "extraSettings.enabledPlugins entries for an unmanaged plugin dropped"

  touch $out
''
