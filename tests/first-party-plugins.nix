# Each first-party hooks plugin passed through from its skill repository is named by its
# manifest, carries the passthru mkMarketplace reads, and holds every script its hooks.json
# runs as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>"`.
# agentree-statusline, built here from its repository's plugin/ folder, is named by its manifest
# too, holds only the paths its `include` lists, every module its hooks.json registers and every
# file its relative imports name, and the files the engine reads at run time.
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

  a=${p.agentree-statusline}
  assert_json $a/.claude-plugin/plugin.json '.name == "agentree-statusline"' "manifest name of $a"
  test "${p.agentree-statusline.claudePluginName}" = agentree-statusline \
    || fail "claudePluginName of $a is ${p.agentree-statusline.claudePluginName}"
  assert_json $a/.claude-plugin/plugin.json '.version == "${p.agentree-statusline.version}"' \
    "passthru version of $a matches its manifest"
  test "${p.agentree-statusline.name}" = "claude-plugin-agentree-statusline-${p.agentree-statusline.version}" \
    || fail "derivation name ${p.agentree-statusline.name}"
  # The listed paths and the hook-mode helper, without plugin/'s tests, tools and npm files.
  test "$(ls -A $a | sort | tr '\n' ' ')" = ".claude-plugin defaults hooks lib src types " \
    || fail "top level of agentree-statusline: $(ls -A $a)"
  modules=$(jq -r '.modules[]' $a/hooks/hooks.json)
  test -n "$modules" || fail "agentree-statusline's hooks.json registers no module"
  while IFS= read -r module; do
    test -f "$a/hooks/$module" || fail "agentree-statusline lacks hooks/$module, which its hooks.json registers"
  done <<< "$modules"
  # Files the engine reads at run time rather than imports.
  for f in defaults/config.jsonc hooks/eta-instruction.md; do
    test -f $a/$f || fail "agentree-statusline lacks $f"
  done
  # Every relative import resolves inside the build: esbuild parses each module and fails on an
  # import it can't resolve. Packages (`claude-code`, `node:*`) stay external, and type-only
  # imports are dropped unresolved.
  ${pkgs.esbuild}/bin/esbuild --bundle --packages=external --platform=node --format=esm \
    --log-level=error --outdir="$TMPDIR/bundle" \
    $(find $a/hooks $a/src -name '*.ts' -not -name '*.d.ts' -o -name '*.tsx') \
    || fail "agentree-statusline has a relative import that doesn't resolve inside the build"

  touch $out
''
