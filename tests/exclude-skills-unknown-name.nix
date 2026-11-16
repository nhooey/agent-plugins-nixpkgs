# excludeSkills naming a skill the plugin doesn't have fails the build, so a rename upstream
# can't silently bring a skill back.
{
  self,
  pkgs,
  helpers,
}:
let
  p = self.packages.${pkgs.stdenv.hostPlatform.system};
  failed = pkgs.testers.testBuildFailure (
    p.superpowers.override { excludeSkills = [ "no-such-skill" ]; }
  );
in
pkgs.runCommand "check-exclude-skills-unknown-name" { } ''
  source ${helpers}
  test "$(cat ${failed}/testBuildFailure.exit)" != 0 || fail "build with an unknown skill succeeded"
  grep -q 'skills/no-such-skill' ${failed}/testBuildFailure.log \
    || fail "build failed for another reason: $(cat ${failed}/testBuildFailure.log)"
  touch $out
''
