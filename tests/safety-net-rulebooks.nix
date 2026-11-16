# Each rulebook in safetyNetRulebooks passes its own `tests` fixtures, run through the packaged
# Safety Net hook as Claude Code runs it, with only that rulebook installed. As in the skill
# repositories' `rulebook test`: a `blocked` fixture must be denied by its own rule
# (`custom.<rulebook>/<rule>`), an `allowed` one must not be denied, and every rule needs a
# `blocked` fixture.
{
  self,
  pkgs,
  helpers,
}:
let
  plugin = self.packages.${pkgs.stdenv.hostPlatform.system}.cc-safety-net;
  checkRulebook = name: rulebook: ''
    echo "rulebook ${name}"
    test "${rulebook.name}" = "${name}" || fail "safetyNetRulebooks.${name} is named ${rulebook.name}"
    export CC_SAFETY_NET_HOME=${self.lib.mkSafetyNetHome pkgs [ rulebook ]}
    check_fixtures ${pkgs.writeText "${name}.json" (builtins.toJSON rulebook)}
  '';
in
pkgs.runCommand "check-safety-net-rulebooks" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}
  export HOME=$TMPDIR
  hook=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' ${plugin}/hooks/hooks.json \
    | sed "s|\''${CLAUDE_PLUGIN_ROOT}|${plugin}|")

  # check_fixtures RULEBOOK-JSON: every fixture's outcome matches; failures are counted in $failed.
  failed=0
  check_fixtures() {
    local rb=$1 name i n command expect rule decision reason
    name=$(jq -r .name "$rb")
    test "$(jq '.tests | length' "$rb")" -gt 0 || fail "$name has no tests"
    for rule in $(jq -r '[.tests[] | select(.expect == "blocked") | .rule] as $c
        | .rules[].name | select(. as $r | $c | index($r) | not)' "$rb"); do
      echo "FAIL: $name: rule $rule has no blocked fixture" >&2
      failed=$((failed + 1))
    done
    n=$(jq '.tests | length' "$rb")
    for ((i = 0; i < n; i++)); do
      command=$(jq -r ".tests[$i].command" "$rb")
      expect=$(jq -r ".tests[$i].expect" "$rb")
      rule=$(jq -r ".tests[$i].rule // \"\"" "$rb")
      jq -nc --arg c "$command" '{session_id:"check",transcript_path:"/tmp/check.jsonl",
        hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},
        cwd:"/tmp",permission_mode:"default"}' | eval "$hook" >$TMPDIR/out \
        || fail "hook exited $? for '$command': $(cat $TMPDIR/out)"
      if test -s $TMPDIR/out; then
        decision=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' $TMPDIR/out)
        reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' $TMPDIR/out)
      else
        decision=allow reason=
      fi
      case $expect in
        blocked)
          if test "$decision" != deny; then
            echo "FAIL: $name: [$command] expected blocked by $rule, was allowed" >&2
            failed=$((failed + 1))
          elif ! grep -qxF "Rule: custom.$name/$rule" <<<"$reason"; then
            echo "FAIL: $name: [$command] expected blocked by $rule, got: $(grep '^Rule:' <<<"$reason")" >&2
            failed=$((failed + 1))
          fi
          ;;
        allowed)
          if test "$decision" = deny; then
            echo "FAIL: $name: [$command] expected allowed, got: $(grep '^Rule:' <<<"$reason")" >&2
            failed=$((failed + 1))
          fi
          ;;
        *) fail "$name: [$command] unknown expect: $expect" ;;
      esac
    done
    echo "$name: $n fixtures checked"
  }

  ${pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList checkRulebook self.safetyNetRulebooks)}
  test $failed = 0 || fail "$failed rulebook fixture failures"
  touch $out
''
