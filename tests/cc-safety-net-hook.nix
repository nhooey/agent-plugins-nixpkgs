# The hook, run as Claude Code runs it, denies rules from both rulebooks and a built-in rule
# from the read-only home, and allows a harmless command.
{
  self,
  pkgs,
  helpers,
}:
let
  plugin = self.packages.${pkgs.stdenv.hostPlatform.system}.cc-safety-net;
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
pkgs.runCommand "check-cc-safety-net-hook" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}
  export HOME=$TMPDIR CC_SAFETY_NET_HOME=${home}
  hook=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' ${plugin}/hooks/hooks.json \
    | sed "s|\''${CLAUDE_PLUGIN_ROOT}|${plugin}|")

  # run COMMAND: feed the hook a PreToolUse event for Bash running COMMAND; stdout to $TMPDIR/out.
  run() {
    status=0
    jq -nc --arg c "$1" '{session_id:"check",transcript_path:"/tmp/check.jsonl",
      hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},
      cwd:"/tmp",permission_mode:"default"}' | eval "$hook" >$TMPDIR/out || status=$?
    test $status = 0 || fail "hook exited $status for '$1': $(cat $TMPDIR/out)"
  }

  # expect_deny COMMAND RULE: the hook denies COMMAND and names RULE.
  expect_deny() {
    run "$1"
    assert_json $TMPDIR/out '.hookSpecificOutput.permissionDecision == "deny"' "'$1' is denied"
    assert_json $TMPDIR/out '.hookSpecificOutput.permissionDecisionReason | contains("Rule: '"$2"'")' \
      "'$1' is denied by $2"
  }

  expect_deny 'git add -A' custom.git-avoid-sweeping-operations/add-sweep
  expect_deny 'git -C repo add -A' custom.check-rules/block-git-add-all
  expect_deny 'git reset --hard' git.reset-hard
  expect_deny 'git stash' custom.git-avoid-sweeping-operations/stash-sweep

  # Allowed: exit 0 (checked by run) and no deny or ask decision.
  run 'git status'
  if test -s $TMPDIR/out; then
    assert_json $TMPDIR/out '(.hookSpecificOutput.permissionDecision // "allow") == "allow"' "'git status' is allowed"
  fi

  touch $out
''
