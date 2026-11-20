# mkClaudePlugin's `include` copies only the paths it lists, skipping any the plugin lacks, and
# still reads the manifest and adds the hook-mode helper. The fixture is a TypeScript-shaped
# plugin: the five default paths of flakeModules.claudePlugin (.claude-plugin/plugin.json,
# hooks, src, types, defaults) are copied whole, nested files included, and its README.md,
# tsconfig.json, package.json, tests/ and node_modules/ are left out.
{
  self,
  pkgs,
  helpers,
}:
let
  src = ./fixtures/include-plugin;
  build = include: self.lib.mkClaudePlugin pkgs { inherit src include; };
  whole = self.lib.mkClaudePlugin pkgs { inherit src; };
  defaults = build [
    ".claude-plugin/plugin.json"
    "defaults"
    "hooks"
    "src"
    "types"
  ];
  manifestOnly = build [ ".claude-plugin/plugin.json" ];
  withMissing = build [
    ".claude-plugin/plugin.json"
    "assets"
    "src"
  ];
in
pkgs.runCommand "check-mk-claude-plugin-include" { nativeBuildInputs = [ pkgs.jq ]; } ''
  source ${helpers}

  test "${defaults.claudePluginName}" = include-check || fail "claudePluginName ${defaults.claudePluginName}"
  test "${defaults.name}" = claude-plugin-include-check-0.1.0 || fail "derivation name ${defaults.name}"

  # Listed and present: copied, nested files included.
  assert_json ${defaults}/.claude-plugin/plugin.json '.name == "include-check"' "manifest copied"
  for f in hooks/hooks.json src/index.ts src/lib/util.ts types/index.d.ts defaults/settings.json lib/hook-mode.sh; do
    test -f ${defaults}/$f || fail "$f missing"
  done
  # Not listed: left out.
  for p in README.md tsconfig.json package.json tests node_modules; do
    assert_missing ${defaults}/$p "unlisted $p"
  done
  test "$(ls -A ${defaults} | sort | tr '\n' ' ')" = ".claude-plugin defaults hooks lib src types " \
    || fail "top level of the include build: $(ls -A ${defaults})"

  # Manifest only: nothing else of the plugin is copied.
  assert_json ${manifestOnly}/.claude-plugin/plugin.json '.name == "include-check"' "manifest-only manifest copied"
  for p in hooks src types defaults; do
    assert_missing ${manifestOnly}/$p "unlisted $p in the manifest-only build"
  done

  # Listed but absent upstream: skipped, not created.
  assert_missing ${withMissing}/assets "absent assets/"
  test -f ${withMissing}/src/lib/util.ts || fail "src/lib/util.ts missing beside a skipped path"

  # Without include, the whole source is copied, as before.
  for f in README.md tsconfig.json package.json tests/index.test.ts node_modules/left-pad/index.js; do
    test -f ${whole}/$f || fail "build without include lost $f"
  done

  touch $out
''
