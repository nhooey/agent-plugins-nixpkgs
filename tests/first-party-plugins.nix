# Each first-party hooks plugin passed through from its skill repository is named by its
# manifest, carries the passthru mkMarketplace reads, and holds every script its hooks.json
# runs as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>"`.
# agentree-statusline, built here from its repository's plugin/ folder, is named by its manifest
# too, holds only the paths its `include` lists, every module its hooks.json registers and every
# file its relative imports name, and the files the engine reads at run time.
# claffeinate, terminal-width and nix-devshell-cached-exports, built here from repositories whose
# root is the plugin, are each named by their manifest, hold only the paths their `include`
# lists, every path their hooks.json reaches through ${CLAUDE_PLUGIN_ROOT}, every module it
# registers and every file their code reads at run time. claffeinate's command finds its shipped
# defaults from the build and both its scripts the pinned jq, and nix-devshell-cached-exports'
# hooks run the pinned command with none on PATH.
{
  self,
  pkgs,
  helpers,
}:
let
  inherit (pkgs) lib;
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
  # Each with the top-level paths its `include` lists and the hook-mode helper's lib/, and the
  # files its code reads at run time rather than naming them in hooks.json.
  fromRoot = [
    {
      drv = p.claffeinate;
      name = "claffeinate";
      top = [
        ".claude-plugin"
        "bin"
        "hooks"
        "lib"
        "share"
        "skills"
      ];
      # The hook runs ../bin/claffeinate, which reads ../share/claffeinate/defaults.conf; the
      # skills run `claffeinate` from bin/, which Claude Code puts on the Bash tool's PATH.
      files = [
        "bin/claffeinate"
        "share/claffeinate/defaults.conf"
        "skills/set/SKILL.md"
        "skills/status/SKILL.md"
      ];
    }
    {
      drv = p.terminal-width;
      name = "terminal-width";
      top = [
        ".claude-plugin"
        "hooks"
        "lib"
        "types"
      ];
      files = [ ];
    }
    {
      drv = p.nix-devshell-cached-exports;
      name = "nix-devshell-cached-exports";
      top = [
        ".claude-plugin"
        "agents"
        "hooks"
        "lib"
      ];
      files = [ "agents/worktree-worker.md" ];
    }
  ];
  ndce = p.nix-devshell-cached-exports;
  # The same derivation pkgs/ builds the plugin's hooks against.
  ndceExe = lib.getExe (
    pkgs.callPackage "${self.inputs.nix-devshell-cached-exports-src}/package.nix" { }
  );
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

  ${lib.concatMapStrings (e: ''
    d=${e.drv}
    m=$d/.claude-plugin/plugin.json
    assert_json $m '.name == "${e.name}"' "manifest name of $d"
    test "${e.drv.claudePluginName}" = "${e.name}" || fail "claudePluginName of $d is ${e.drv.claudePluginName}"
    assert_json $m '.version == "${e.drv.version}"' "passthru version of $d matches its manifest"
    test "${e.drv.name}" = "claude-plugin-${e.name}-${e.drv.version}" || fail "derivation name ${e.drv.name}"
    test "$(ls -A $d | sort | tr '\n' ' ')" = "${lib.concatStringsSep " " e.top} " \
      || fail "top level of ${e.name}: $(ls -A $d)"

    # Every path a hook command reaches through ''${CLAUDE_PLUGIN_ROOT}: a file when bash runs
    # it, an executable when the command runs it directly.
    commands=$(jq -r '(.hooks // {})[][].hooks[].command' $d/hooks/hooks.json)
    while IFS= read -r command; do
      test -n "$command" || continue
      path=$(echo "$command" | sed -n 's|.*''${CLAUDE_PLUGIN_ROOT}"\{0,1\}/\([^" ]*\).*|\1|p')
      test -n "$path" || fail "${e.name} hook command reaches nothing in the plugin: $command"
      case "$command" in
      "bash "*) test -f "$d/$path" || fail "${e.name} lacks $path, which its hooks.json runs" ;;
      *) test -x "$d/$path" || fail "${e.name} lacks an executable $path, which its hooks.json runs" ;;
      esac
    done <<< "$commands"
    modules=$(jq -r '(.modules // [])[]' $d/hooks/hooks.json)
    while IFS= read -r module; do
      test -z "$module" || test -f "$d/hooks/$module" \
        || fail "${e.name} lacks hooks/$module, which its hooks.json registers"
    done <<< "$modules"
    test -n "$commands$modules" || fail "${e.name}'s hooks.json runs and registers nothing"
    types=$(jq -r '.types // empty' $m)
    test -z "$types" || test -f "$d/$types" || fail "${e.name} lacks $types, which its manifest names"
    for f in ${lib.escapeShellArgs e.files}; do
      test -f $d/$f || fail "${e.name} lacks $f"
    done
    # Every relative import of a mod module resolves inside the build, as for agentree-statusline.
    ts=$(find $d/hooks -name '*.ts' -not -name '*.d.ts' -o -name '*.tsx')
    test -z "$ts" || ${pkgs.esbuild}/bin/esbuild --bundle --packages=external --platform=node \
      --format=esm --log-level=error --outdir="$TMPDIR/bundle-${e.name}" $ts \
      || fail "${e.name} has a relative import that doesn't resolve inside the build"
  '') fromRoot}

  # claffeinate's command, run from the build, finds the defaults file shipped beside it.
  env -i HOME=$TMPDIR PATH=${pkgs.coreutils}/bin ${pkgs.bash}/bin/bash \
    ${p.claffeinate}/bin/claffeinate config --defaults > defaults.conf \
    || fail "claffeinate config --defaults failed from the build"
  cmp defaults.conf ${p.claffeinate}/share/claffeinate/defaults.conf \
    || fail "claffeinate config --defaults didn't print the shipped defaults file"

  # claffeinate's hook and command find the pinned jq first on their PATH.
  for f in hooks/claffeinate-hook.sh bin/claffeinate; do
    grep -qxF 'PATH="${lib.getBin pkgs.jq}/bin:$PATH"' ${p.claffeinate}/$f \
      || fail "claffeinate's $f doesn't put the pinned jq on its PATH"
  done

  # nix-devshell-cached-exports' hooks run the command built from the same pin, with no
  # nix-devshell-cached-exports on PATH: in a Nix project the SubagentStart and PreToolUse
  # hooks give their context, and SessionStart's CLAUDE_ENV_FILE lines name the pinned command.
  mkdir project && touch project/flake.nix env-file
  run_hook() {
    echo "{\"cwd\": \"$PWD/project\", \"tool_input\": {\"command\": \"nix develop --command true\"}}" \
      | env -i HOME=$TMPDIR PATH=${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin \
          CLAUDE_PLUGIN_ROOT=${ndce} CLAUDE_ENV_FILE=$PWD/env-file \
          ${pkgs.bash}/bin/bash ${ndce}/hooks/$1.sh 2>/dev/null
  }
  for hook in subagent-start pre-tool-use; do
    run_hook $hook | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null \
      || fail "nix-devshell-cached-exports' $hook hook gave no context without the command on PATH"
  done
  run_hook session-start || fail "nix-devshell-cached-exports' session-start hook failed"
  test "$(grep -cF 'command -v ${ndceExe} ' env-file)" = 2 \
    || fail "session-start's CLAUDE_ENV_FILE lines don't name the pinned command: $(cat env-file)"

  touch $out
''
