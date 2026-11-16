# mkSafetyNetHome writes rule.json naming each rulebook, and each rulebook as a regular file
# (Safety Net refuses symlinked config) holding exactly the attribute set given.
{
  self,
  pkgs,
  helpers,
}:
let
  rulebooks = [
    {
      rulebook_version = 1;
      name = "first";
      version = "1.0.0";
      allowed_commands = [ "git" ];
      rules = [ ];
    }
    {
      rulebook_version = 1;
      name = "second";
      version = "2.0.0";
      allowed_commands = [ "rm" ];
      rules = [ ];
    }
  ];
  home = self.lib.mkSafetyNetHome pkgs rulebooks;
in
pkgs.runCommand "check-safety-net-home" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}
  assert_json ${home}/rules/rule.json '. == {version: 1, rules: ["first", "second"]}' "rule.json"
  ${pkgs.lib.concatMapStrings (r: ''
    f=${home}/rules/${r.name}/rulebook.json
    test -f $f && ! test -L $f || fail "$f is not a regular file"
    diff <(jq -S . $f) <(echo ${pkgs.lib.escapeShellArg (builtins.toJSON r)} | jq -S .) || fail "$f content"
  '') rulebooks}
  ! test -L ${home}/rules/rule.json || fail "rule.json is a symlink"
  test "$(ls ${home}/rules | sort | tr '\n' ' ')" = "first rule.json second " || fail "unexpected entries in rules/: $(ls ${home}/rules)"
  touch $out
''
