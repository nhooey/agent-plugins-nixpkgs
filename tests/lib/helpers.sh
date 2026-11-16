# Shared by the checks in tests/. Source it at the top of a runCommand script.
# runCommand's `set -e` ignores a failing `! cmd`, so negative assertions go through these.

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# assert_json FILE JQ-FILTER DESCRIPTION: FILTER must yield true on FILE.
assert_json() {
  jq -e "$2" "$1" >/dev/null || fail "$3 (jq '$2' on $1 gave $(jq -c "$2" "$1" 2>&1))"
}

# assert_missing PATH DESCRIPTION
assert_missing() {
  if test -e "$1" || test -L "$1"; then fail "$2: $1 exists"; fi
}
