# git-push-force-safely-hooks is git-skills' own package, and works as a global core.hooksPath:
# it holds forward-hook and pre-push, every entry is executable, and a commit in a repository
# that has its own pre-commit and commit-msg hooks runs them through it.
{
  self,
  pkgs,
  helpers,
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  hooks = self.packages.${system}.git-push-force-safely-hooks;
  upstream = self.inputs.git-skills.packages.${system}.git-push-force-safely-hooks;
in
assert hooks.outPath == upstream.outPath;
pkgs.runCommand "check-git-push-force-safely-hooks" { nativeBuildInputs = [ pkgs.git ]; } ''
  source ${helpers}

  h=${hooks}
  for f in forward-hook pre-push pre-commit commit-msg; do
    test -f $h/$f || fail "git-push-force-safely-hooks lacks $f"
  done
  for f in $h/*; do
    test -x $f || fail "$f isn't executable"
  done

  export HOME=$TMPDIR GIT_CONFIG_NOSYSTEM=1
  git config --global core.hooksPath $h
  git config --global user.name test
  git config --global user.email test@example.com
  git init -q repo
  printf '#!/bin/sh\ntouch "$(git rev-parse --git-dir)/pre-commit-ran"\n' > repo/.git/hooks/pre-commit
  printf '#!/bin/sh\necho "$1" > "$(git rev-parse --git-dir)/commit-msg-arg"\n' > repo/.git/hooks/commit-msg
  chmod +x repo/.git/hooks/pre-commit repo/.git/hooks/commit-msg
  git -C repo commit -q --allow-empty -m forwarded
  test -f repo/.git/pre-commit-ran || fail "the repository's own pre-commit didn't run"
  grep -q COMMIT_EDITMSG repo/.git/commit-msg-arg \
    || fail "the repository's own commit-msg didn't get its argument: $(cat repo/.git/commit-msg-arg)"

  # A failing hook of the repository's own stops the commit.
  printf '#!/bin/sh\nexit 1\n' > repo/.git/hooks/pre-commit
  if git -C repo commit -q --allow-empty -m refused 2>/dev/null; then
    fail "a commit went through though the repository's own pre-commit failed"
  fi

  touch $out
''
