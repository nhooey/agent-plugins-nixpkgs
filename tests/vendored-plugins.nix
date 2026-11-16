# Each vendored plugin is built from its own manifest, cc-safety-net's hook runs a pinned node,
# and excludeSkills removes exactly the skills it names.
{
  self,
  pkgs,
  helpers,
}:
let
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  trimmed = p.superpowers.override { excludeSkills = [ "diagnosing-superpowers" ]; };
  # package, the name its manifest must give, and the passthru mkClaudePlugin set from it.
  expected = [
    {
      drv = p.cc-safety-net;
      name = "cc-safety-net";
    }
    {
      drv = p.superpowers;
      name = "superpowers";
    }
    {
      drv = p.trailofbits-insecure-defaults;
      name = "insecure-defaults";
    }
    {
      drv = p.trailofbits-sharp-edges;
      name = "sharp-edges";
    }
    {
      drv = p.trailofbits-spec-to-code-compliance;
      name = "spec-to-code-compliance";
    }
  ];
in
pkgs.runCommand "check-vendored-plugins" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}

  ${pkgs.lib.concatMapStrings (e: ''
    m=${e.drv}/.claude-plugin/plugin.json
    assert_json $m '.name == "${e.name}"' "manifest name of ${e.drv}"
    test "${e.drv.claudePluginName}" = "${e.name}" || fail "claudePluginName of ${e.drv} is ${e.drv.claudePluginName}"
    assert_json $m '.version == "${e.drv.version}"' "passthru version of ${e.drv} matches its manifest"
    test "${e.drv.name}" = "claude-plugin-${e.name}-${e.drv.version}" || fail "derivation name ${e.drv.name}"
  '') expected}

  # postPatch pointed the hook at the store's node, not whatever node is on PATH.
  assert_json ${p.cc-safety-net}/hooks/hooks.json \
    '.hooks.PreToolUse[0].hooks[0].command | startswith("${pkgs.nodejs}/bin/node ")' \
    "cc-safety-net hook runs ${pkgs.nodejs}/bin/node"

  # Without excludeSkills every upstream skill is kept; with it, the named skill goes and every
  # other one stays. Compared with the source, so a build that drops extra skills can't pass.
  upstream=$(ls ${self.inputs.superpowers-src}/skills)
  test "$(ls ${p.superpowers}/skills)" = "$upstream" || fail "superpowers skills differ from upstream"
  echo "$upstream" | grep -qx diagnosing-superpowers || fail "upstream no longer has diagnosing-superpowers; pick another skill to exclude"
  assert_missing ${trimmed}/skills/diagnosing-superpowers "excluded skill"
  want=$(echo "$upstream" | grep -vx diagnosing-superpowers)
  got=$(ls ${trimmed}/skills)
  test "$want" = "$got" || fail "trimmed superpowers skills differ: want [$want] got [$got]"

  touch $out
''
