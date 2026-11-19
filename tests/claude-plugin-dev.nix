# lib.claudePluginDevCommand: its core's unit tests pass, and its command, run in a subdirectory
# of a fixture repository with a stub `claude` that records its arguments, starts `claude` with a
# `--plugin-dir` per local plugin and its own arguments after them, or, when fixture managed
# settings name a plugin of the same name, stops without starting it: for an entry the module
# wrote it names the unmanaged line to add, and for any other it says to remove the entry.
{
  self,
  pkgs,
  helpers,
}:
let
  command = self.lib.claudePluginDevCommand pkgs;
  fixtures = ./fixtures/claude-plugin-dev;
  # Records its arguments, one per line, and whether the wrapper's git variable reached it.
  claudeStub = pkgs.writeShellScriptBin "claude" ''
    printf '%s\n' "$@" >"$CLAUDE_ARGS"
    printf '%s\n' "''${CLAUDE_PLUGIN_DEV_GIT-unset}" >"$CLAUDE_ARGS.git"
  '';
in
assert pkgs.lib.assertMsg (command.name == "claude-plugin-dev") "the command's name";
pkgs.runCommand "check-claude-plugin-dev"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.git
      claudeStub
      command.package
    ];
  }
  ''
    source ${helpers}
    PYTHONPATH=${../scripts} python3 -m unittest discover -s ${./.} -p 'test_claude_plugin_dev.py' -v

    export HOME="$TMPDIR/home"
    cp -R ${fixtures}/repo repo
    chmod -R u+w repo
    git -C repo init --quiet
    root=$(git -C repo rev-parse --show-toplevel)
    cd repo/plugins

    # Unlocked: one --plugin-dir per local plugin, then the arguments, quoting intact.
    CLAUDE_ARGS="$TMPDIR/unlocked" CLAUDE_PLUGIN_DEV_MANAGED_SETTINGS=${fixtures}/managed-unlocked \
      claude-plugin-dev --model opus "two words"
    printf '%s\n' --plugin-dir "$root/plugins/alpha" --plugin-dir "$root/beta" --model opus "two words" >"$TMPDIR/want"
    diff "$TMPDIR/want" "$TMPDIR/unlocked" || fail "claude's arguments with unlocked managed settings"
    test "$(cat "$TMPDIR/unlocked.git")" = unset || fail "CLAUDE_PLUGIN_DEV_GIT reached claude"

    # No managed settings folder at all: nothing is locked.
    CLAUDE_ARGS="$TMPDIR/absent" CLAUDE_PLUGIN_DEV_MANAGED_SETTINGS="$TMPDIR/no-such-folder" \
      claude-plugin-dev
    printf '%s\n' --plugin-dir "$root/plugins/alpha" --plugin-dir "$root/beta" >"$TMPDIR/want"
    diff "$TMPDIR/want" "$TMPDIR/absent" || fail "claude's arguments with no managed settings"

    # run_locked FIXTURE: claude-plugin-dev with the managed settings in FIXTURE must fail
    # without starting claude; its stderr is left in $TMPDIR/FIXTURE.err.
    run_locked() {
      if CLAUDE_ARGS="$TMPDIR/$1" CLAUDE_PLUGIN_DEV_MANAGED_SETTINGS="${fixtures}/$1" \
        claude-plugin-dev --model opus 2>"$TMPDIR/$1.err"; then
        fail "claude-plugin-dev succeeded with the managed settings in $1"
      fi
      assert_missing "$TMPDIR/$1" "claude started with the managed settings in $1"
    }
    # says FIXTURE TEXT: the stderr of run_locked FIXTURE holds the line TEXT.
    says() {
      grep -qxF -- "$2" "$TMPDIR/$1.err" || fail "$1's message lacks '$2': $(cat "$TMPDIR/$1.err")"
    }
    # never_says FIXTURE TEXT: it holds no TEXT anywhere.
    never_says() {
      if grep -qF -- "$2" "$TMPDIR/$1.err"; then fail "$1's message says '$2': $(cat "$TMPDIR/$1.err")"; fi
    }

    # The module's drop-in enables alpha@nix-pinned: add the unmanaged line.
    run_locked managed-locked
    says managed-locked "  alpha: ${fixtures}/managed-locked/managed-settings.d/40-agent-plugins.json enables alpha@nix-pinned"
    says managed-locked '  services.agent-plugins.unmanaged = [ "alpha" ];'
    never_says managed-locked "Remove"

    # The module's drop-in sets beta@nix-pinned to false, which locks it as well.
    run_locked managed-false
    says managed-false "  beta: ${fixtures}/managed-false/managed-settings.d/40-agent-plugins.json disables beta@nix-pinned"
    says managed-false '  services.agent-plugins.unmanaged = [ "beta" ];'

    # Entries the module didn't write, in managed-settings.json and another drop-in (whose
    # Beta matches beta despite the case): remove each from its file, and no unmanaged line.
    run_locked managed-elsewhere
    says managed-elsewhere "Remove \`alpha@nix-pinned\` from ${fixtures}/managed-elsewhere/managed-settings.json."
    says managed-elsewhere "Remove \`Beta@company\` from ${fixtures}/managed-elsewhere/managed-settings.d/50-command-guards.json."
    never_says managed-elsewhere "services.agent-plugins.unmanaged"

    touch $out
  ''
