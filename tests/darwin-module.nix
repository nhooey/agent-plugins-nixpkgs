# The nix-darwin module, evaluated by tests/lib/darwin-activation.nix, writes a
# drop-in that installs the marketplace of managed and user plugins, enables only the managed
# ones, points Safety Net at the rulebooks, points AGENT_HOOK_MODES at hook-modes.json and merges
# extraSettings; disabled, it writes nothing.
# The old `plugins` name still sets managedPlugins, with a warning, and merges with the new one.
# A plugin name listed twice, in one list or across both, fails an assertion, and so does a user
# plugin set in extraSettings.enabledPlugins.
{
  self,
  pkgs,
  helpers,
  evalConfig,
  activationText,
}:
let
  inherit (pkgs) lib;
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  failedAssertions =
    cfg: map (a: a.message) (lib.filter (a: !a.assertion) (evalConfig cfg).assertions);
  enabledCfg = {
    enable = true;
    managedPlugins = [ p.cc-safety-net ];
    userPlugins = [ p.superpowers ];
    marketplaceName = "check-market";
    marketplaceOwner = "check-owner";
    dropInName = "50-check.json";
    ccSafetyNet.rulebooks = [ self.safetyNetRulebooks.git-avoid-sweeping-operations ];
    ccSafetyNet.transparentWrappers = [ "nix" ];
    hookModes = {
      check-guard = "deny";
      check-lint = "off";
    };
    extraSettings = {
      env.CHECK_VAR = "1";
      permissions.deny = [ "Bash(rm -rf /)" ];
    };
  };
  enabled = pkgs.writeText "activation-enabled" (activationText enabledCfg);
  oldNameCfg = {
    enable = true;
    plugins = [ p.superpowers ];
  };
  oldName = pkgs.writeText "activation-old-name" (activationText oldNameCfg);
  oldNameWarnings = (evalConfig oldNameCfg).warnings;
  bothNames = pkgs.writeText "activation-both-names" (activationText {
    enable = true;
    plugins = [ p.superpowers ];
    managedPlugins = [ p.cc-safety-net ];
  });
  userOnly = pkgs.writeText "activation-user-only" (activationText {
    enable = true;
    userPlugins = [
      p.superpowers
      p.agentree-statusline
    ];
  });
  # A different build of superpowers, with the same plugin name.
  trimmedSuperpowers = p.superpowers.override { excludeSkills = [ "diagnosing-superpowers" ]; };
  acrossLists = failedAssertions {
    enable = true;
    managedPlugins = [
      p.cc-safety-net
      p.superpowers
    ];
    userPlugins = [ trimmedSuperpowers ];
  };
  withinOneList = failedAssertions {
    enable = true;
    managedPlugins = [
      p.cc-safety-net
      p.cc-safety-net
      p.cc-safety-net
    ];
  };
  # failedAssertions when extraSettings.enabledPlugins sets superpowers, a user plugin, to VALUE.
  extraEnables =
    value:
    failedAssertions {
      enable = true;
      marketplaceName = "check-market";
      managedPlugins = [ p.cc-safety-net ];
      userPlugins = [ p.superpowers ];
      extraSettings.enabledPlugins."superpowers@check-market" = value;
    };
  # MESSAGES is exactly one failed assertion, naming NAME once.
  namesOnce =
    name: messages:
    lib.length messages == 1 && lib.length (lib.splitString name (lib.head messages)) == 2;
  disabled = activationText {
    enable = false;
    managedPlugins = [ p.superpowers ];
  };
  dropIns = "/Library/Application Support/ClaudeCode/managed-settings.d";
in
assert lib.assertMsg (disabled == "") "the disabled module still writes an activation script";
assert lib.assertMsg (
  failedAssertions enabledCfg == [ ]
) "disjoint managedPlugins and userPlugins fail an assertion";
assert lib.assertMsg (namesOnce "superpowers" acrossLists)
  "another build of a managed plugin in userPlugins doesn't fail one assertion naming it once: ${builtins.toJSON acrossLists}";
assert lib.assertMsg (namesOnce "cc-safety-net" withinOneList)
  "a plugin listed thrice in managedPlugins doesn't fail one assertion naming it once: ${builtins.toJSON withinOneList}";
assert lib.assertMsg (namesOnce "superpowers@check-market" (extraEnables true))
  "extraSettings enabling a user plugin doesn't fail one assertion naming it: ${builtins.toJSON (extraEnables true)}";
assert lib.assertMsg (namesOnce "superpowers@check-market" (extraEnables false))
  "extraSettings disabling a user plugin doesn't fail one assertion naming it: ${builtins.toJSON (extraEnables false)}";
assert lib.assertMsg (lib.any
  (w: lib.hasInfix "services.agent-plugins.plugins" w && lib.hasInfix "managedPlugins" w)
  oldNameWarnings
) "the old plugins name doesn't warn of its rename: ${builtins.toJSON oldNameWarnings}";
pkgs.runCommand "check-darwin-module" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}

  # settings_of ACTIVATION DROP-IN: the settings file ACTIVATION installs as DROP-IN.
  settings_of() {
    line=$(grep -F '"${dropIns}/'"$2"'"' "$1") || fail "$1 doesn't install ${dropIns}/$2: $(cat "$1")"
    echo "$line" | grep -o '/nix/store/[^ ]*-claude-agent-plugins.json'
  }

  s=$(settings_of ${enabled} 50-check.json)
  assert_json $s '.enabledPlugins == {"cc-safety-net@check-market": true}' "enabledPlugins holds the managed plugin only"
  assert_json $s '.extraKnownMarketplaces | keys == ["check-market"]' "one known marketplace"
  assert_json $s '.extraKnownMarketplaces["check-market"].source.source == "directory"' "marketplace source kind"
  market=$(jq -r '.extraKnownMarketplaces["check-market"].source.path' $s)
  assert_json $market/.claude-plugin/marketplace.json \
    '.name == "check-market" and .owner.name == "check-owner" and ([.plugins[].name] == ["cc-safety-net", "superpowers"])' \
    "the marketplace the drop-in points at lists the managed and the user plugin"
  home=$(jq -r '.env.CC_SAFETY_NET_HOME' $s)
  assert_json $home/rules/rule.json '.rules == ["git-avoid-sweeping-operations"]' "CC_SAFETY_NET_HOME rulebooks"
  assert_json $home/rules/rule.json '.transparent_wrappers == ["nix"]' "CC_SAFETY_NET_HOME transparent wrappers"
  modes=$(jq -r '.env.AGENT_HOOK_MODES' $s)
  case "$modes" in /nix/store/*-hook-modes.json) ;; *) fail "AGENT_HOOK_MODES is $modes" ;; esac
  assert_json $modes '. == {"check-guard": "deny", "check-lint": "off"}' "hook-modes.json from hookModes"
  assert_json $s '.env.CHECK_VAR == "1"' "extraSettings env merged beside CC_SAFETY_NET_HOME"
  assert_json $s '.permissions.deny == ["Bash(rm -rf /)"]' "extraSettings permissions"

  s=$(settings_of ${oldName} 40-agent-plugins.json)
  assert_json $s '.enabledPlugins == {"superpowers@nix-pinned": true}' "the old plugins name, and the default marketplace name"
  assert_json $s '.env | keys == ["AGENT_HOOK_MODES"]' "no CC_SAFETY_NET_HOME without rulebooks"
  assert_json "$(jq -r '.env.AGENT_HOOK_MODES' $s)" '. == {}' "hook-modes.json without hookModes"
  assert_json "$(jq -r '.extraKnownMarketplaces["nix-pinned"].source.path' $s)/.claude-plugin/marketplace.json" \
    '.owner.name == "nix"' "default marketplace owner"

  s=$(settings_of ${bothNames} 40-agent-plugins.json)
  assert_json $s '.enabledPlugins == {"cc-safety-net@nix-pinned": true, "superpowers@nix-pinned": true}' \
    "the old plugins name merges into managedPlugins"

  s=$(settings_of ${userOnly} 40-agent-plugins.json)
  assert_json $s '.enabledPlugins == {}' "user plugins only: nothing enabled"
  market=$(jq -r '.extraKnownMarketplaces["nix-pinned"].source.path' $s)
  assert_json $market/.claude-plugin/marketplace.json \
    '[.plugins[].name] == ["superpowers", "agentree-statusline"]' "user plugins only: the marketplace is still registered and lists them"
  # Each module the mod's hooks.json registers is in the marketplace copy.
  hooks=$market/agentree-statusline/hooks
  modules=$(jq -r '.modules[]' $hooks/hooks.json)
  test -n "$modules" || fail "agentree-statusline@nix-pinned registers no module"
  while IFS= read -r module; do
    test -f "$hooks/$module" || fail "agentree-statusline@nix-pinned lacks hooks/$module"
  done <<< "$modules"

  touch $out
''
