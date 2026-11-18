# The hook `check-guard`: a PreToolUse guard against any command holding the word "forbidden",
# written the way a blocking hook reads its mode. At `deny` it denies the call; at `remind` it
# adds context saying what it would have denied and lets the call run; at `off` it exits at once.
# shellcheck source=../../../../lib/hook-mode.sh
source "${CLAUDE_PLUGIN_ROOT}/lib/hook-mode.sh"

mode=$(hook_mode check-guard)
[ "$mode" = off ] && exit 0

grep -q forbidden || exit 0

reason='check-guard: the command holds the word "forbidden".'
case "$mode" in
deny)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${reason//\"/\\\"}"
  ;;
*)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "This call goes ahead; at deny it would have been denied. ${reason//\"/\\\"}"
  ;;
esac
