# Each first-party hooks plugin passed through from its skill repository is named by its
# manifest, carries the passthru mkMarketplace reads, and holds every script its hooks.json
# runs as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>"`.
{
  self,
  pkgs,
  helpers,
}:
let
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  expected = [
    {
      drv = p.coding-agent-skills-hooks;
      name = "coding-agent-skills-hooks";
    }
    {
      drv = p.git-skills-hooks;
      name = "git-skills-hooks";
    }
  ];
in
pkgs.runCommand "check-first-party-plugins" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}

  ${pkgs.lib.concatMapStrings (e: ''
    m=${e.drv}/.claude-plugin/plugin.json
    assert_json $m '.name == "${e.name}"' "manifest name of ${e.drv}"
    test "${e.drv.claudePluginName}" = "${e.name}" || fail "claudePluginName of ${e.drv} is ${e.drv.claudePluginName}"
    assert_json $m '.version == "${e.drv.version}"' "passthru version of ${e.drv} matches its manifest"

    h=${e.drv}/hooks/hooks.json
    commands=$(jq -r '.hooks[][].hooks[].command' $h)
    test -n "$commands" || fail "${e.name} has no hook commands"
    while IFS= read -r command; do
      script=$(echo "$command" | sed -n 's|^bash "''${CLAUDE_PLUGIN_ROOT}/\(scripts/[^"]*\)"$|\1|p')
      test -n "$script" || fail "${e.name} hook command doesn't run a plugin script with bash: $command"
      test -f "${e.drv}/$script" || fail "${e.name} lacks $script, which its hooks.json runs"
    done <<< "$commands"
  '') expected}

  touch $out
''
