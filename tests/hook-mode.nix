# A test plugin's hook (tests/fixtures/hook-mode-plugin), built with mkClaudePlugin and run the
# way Claude Code runs it with AGENT_HOOK_MODES from the nix-darwin module's drop-in, denies at
# `deny`, adds context at `remind` and is silent at `off`. With no hookModes set, or no file, or
# a name or value the file lacks, every hook reports `remind`. Every plugin mkClaudePlugin builds
# carries the helper with its jq pinned, so a hook needs no jq on PATH.
{
  self,
  pkgs,
  helpers,
  activationText,
}:
let
  inherit (pkgs) lib;
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  plugin = self.lib.mkClaudePlugin pkgs { src = ./fixtures/hook-mode-plugin; };
  # The activation script the module writes for these hookModes, with the test plugin installed.
  activation =
    name: hookModes:
    pkgs.writeText "activation-${name}" (activationText {
      enable = true;
      managedPlugins = [ plugin ];
      inherit hookModes;
    });
  withModes = mode: activation mode { check-guard = mode; };
  unset = activation "unset" { };
  # Hooks that can deny today, by the names the README lists; none is set in `unset`.
  denyingHooks = [
    "check-guard"
    "scratchpad-guard"
    "browser-check"
    "reply-lint"
  ];
  badValue = pkgs.writeText "hook-modes.json" (builtins.toJSON { check-guard = "block"; });
  # Plugins mkClaudePlugin builds in this flake; the other first-party ones are built in their own.
  builtHere = [
    plugin
    p.agentree-statusline
    p.cc-safety-net
    p.superpowers
    p.trailofbits-insecure-defaults
    p.trailofbits-sharp-edges
    p.trailofbits-spec-to-code-compliance
  ];
in
pkgs.runCommand "check-hook-mode" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}

  # modes_of ACTIVATION: the AGENT_HOOK_MODES path in the drop-in ACTIVATION installs.
  modes_of() {
    s=$(grep -o '/nix/store/[^ ]*-claude-agent-plugins.json' "$1") || fail "$1 installs no drop-in"
    jq -er '.env.AGENT_HOOK_MODES' "$s" || fail "$s has no env.AGENT_HOOK_MODES"
  }

  # run_hook MODES COMMAND: the test plugin's hook given a Bash call of COMMAND, with
  # AGENT_HOOK_MODES=MODES (empty: unset) and no jq on PATH.
  run_hook() {
    jq -n --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}' \
      | env -i PATH=${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin CLAUDE_PLUGIN_ROOT=${plugin} \
          ''${1:+AGENT_HOOK_MODES=$1} ${pkgs.bash}/bin/bash ${plugin}/scripts/check-guard.sh
  }

  # mode_of MODES NAME: the helper's answer, run as a command, with AGENT_HOOK_MODES=MODES.
  mode_of() {
    env -i PATH=${pkgs.coreutils}/bin ''${1:+AGENT_HOOK_MODES=$1} ${pkgs.bash}/bin/bash ${plugin}/lib/hook-mode.sh "$2"
  }

  ${lib.concatMapStrings (d: ''
    test -f ${d}/lib/hook-mode.sh || fail "${d} lacks lib/hook-mode.sh"
    if grep -q '@jq@' ${d}/lib/hook-mode.sh; then fail "${d}/lib/hook-mode.sh still holds @jq@"; fi
  '') builtHere}

  # deny: denied, by name; a harmless command passes in silence.
  got=$(run_hook "$(modes_of ${withModes "deny"})" 'echo forbidden')
  echo "$got" | jq -e '.hookSpecificOutput.permissionDecision == "deny"
    and (.hookSpecificOutput.permissionDecisionReason | contains("check-guard"))' >/dev/null \
    || fail "deny: the hook didn't deny: $got"
  got=$(run_hook "$(modes_of ${withModes "deny"})" 'echo fine')
  test -z "$got" || fail "deny: a harmless command gave output: $got"

  # remind: context saying what it would have denied, and no decision.
  got=$(run_hook "$(modes_of ${withModes "remind"})" 'echo forbidden')
  echo "$got" | jq -e '(.hookSpecificOutput | has("permissionDecision") | not)
    and (.hookSpecificOutput.additionalContext | contains("would have been denied"))' >/dev/null \
    || fail "remind: the hook didn't only add context: $got"

  # off: silent.
  got=$(run_hook "$(modes_of ${withModes "off"})" 'echo forbidden')
  test -z "$got" || fail "off: the hook gave output: $got"

  # No hookModes: the file is {} and every hook reports remind; the test hook reminds.
  unset=$(modes_of ${unset})
  assert_json "$unset" '. == {}' "hook-modes.json with no hookModes"
  ${lib.concatMapStrings (name: ''
    test "$(mode_of "$unset" ${name})" = remind || fail "${name} with no hookModes: $(mode_of "$unset" ${name})"
  '') denyingHooks}
  got=$(run_hook "$unset" 'echo forbidden')
  echo "$got" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null \
    || fail "no hookModes: the hook didn't remind: $got"

  # A missing variable, a missing file and a value that isn't a mode all read as remind.
  test "$(mode_of "" check-guard)" = remind || fail "AGENT_HOOK_MODES unset: $(mode_of "" check-guard)"
  test "$(mode_of /nonexistent/hook-modes.json check-guard)" = remind || fail "missing file"
  test "$(mode_of ${badValue} check-guard)" = remind || fail "a value that isn't a mode"
  test "$(mode_of "$(modes_of ${withModes "deny"})" check-guard)" = deny || fail "run as a command"

  touch $out
''
