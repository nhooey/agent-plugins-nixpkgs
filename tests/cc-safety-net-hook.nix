# The hook, run as Claude Code runs it, denies rules from every rulebook and a built-in rule
# from the read-only home, applies a rule to its command run through `nix`, a transparent
# wrapper, and allows harmless commands.
{
  self,
  pkgs,
  helpers,
}:
let
  plugin = self.packages.${pkgs.stdenv.hostPlatform.system}.cc-safety-net;
  home = self.lib.mkSafetyNetHome pkgs {
    rulebooks = [
      self.safetyNetRulebooks.git-avoid-sweeping-operations
      self.safetyNetRulebooks.git-avoid-sweeping-operations-with-exclusions
      {
        rulebook_version = 1;
        name = "check-rules";
        version = "1.0.0";
        allowed_commands = [ "git" ];
        rules = [
          {
            name = "block-git-describe-dirty";
            command = "git";
            subcommand = "describe";
            block_args = [ "--dirty" ];
            reason = "check";
          }
        ];
      }
      {
        rulebook_version = 2;
        name = "check-paths";
        version = "1.0.0";
        allowed_commands = [ "op" ];
        rules = [
          {
            name = "op-item-get-format";
            command = "op";
            match = {
              command_path = [
                "item"
                "get"
              ];
              any_args = [
                "--format"
                "--format=json"
              ];
            };
            reason = "check";
          }
        ];
      }
    ];
    transparentWrappers = [ "nix" ];
  };
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
  expect_deny 'git describe --dirty' custom.check-rules/block-git-describe-dirty
  expect_deny 'git reset --hard' git.reset-hard
  expect_deny 'git stash' custom.git-avoid-sweeping-operations-with-exclusions/stash-sweep
  expect_deny 'op item get X --format json' custom.check-paths/op-item-get-format
  expect_deny 'nix develop --command op item get X --format json' custom.check-paths/op-item-get-format

  # expect_allow COMMAND: exit 0 (checked by run) and no deny or ask decision.
  expect_allow() {
    run "$1"
    if test -s $TMPDIR/out; then
      assert_json $TMPDIR/out '(.hookSpecificOutput.permissionDecision // "allow") == "allow"' "'$1' is allowed"
    fi
  }

  expect_allow 'git status'
  expect_allow 'op item list --format json'
  expect_allow 'nix develop --command op item list --format json'

  touch $out
''
