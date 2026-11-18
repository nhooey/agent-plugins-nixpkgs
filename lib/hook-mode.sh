# hook_mode NAME: prints the mode of the hook NAME, `off`, `remind` or `deny`, from the JSON
# object in the file AGENT_HOOK_MODES names, which the nix-darwin module writes from
# services.agent-plugins.hookModes. It prints `remind` when the variable, the file or the name is
# missing, or the value isn't one of the three, so a hook nobody has set only reminds.
#
# mkClaudePlugin copies this file into every plugin as lib/hook-mode.sh, with @jq@ replaced by a
# store path. A bash hook sources it:
#   source "${CLAUDE_PLUGIN_ROOT}/lib/hook-mode.sh"
#   case "$(hook_mode scratchpad-guard)" in off) exit 0 ;; ... esac
# and a hook in another language runs it: `bash "${CLAUDE_PLUGIN_ROOT}/lib/hook-mode.sh" NAME`.
#
# A hook at `deny` denies; at `remind` it adds context saying what it would have denied and lets
# the action run; at `off` it exits at once.

hook_mode() {
  local mode=""
  if [ -n "${AGENT_HOOK_MODES:-}" ] && [ -r "$AGENT_HOOK_MODES" ]; then
    mode=$(@jq@ -r --arg name "$1" '.[$name] // empty | strings' "$AGENT_HOOK_MODES" 2>/dev/null) || mode=""
  fi
  case "$mode" in
  off | remind | deny) printf '%s\n' "$mode" ;;
  *) printf 'remind\n' ;;
  esac
}

# Run as a command rather than sourced: print the mode of the hook named by the one argument.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -ne 1 ]; then
    echo "usage: bash hook-mode.sh HOOK-NAME" >&2
    exit 2
  fi
  hook_mode "$1"
fi
