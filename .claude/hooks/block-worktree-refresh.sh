#!/usr/bin/env bash
# ---
# name: block-worktree-refresh
# event: PreToolUse
# matcher: Bash
# description: Report an early advisory for a plain project-writing kendex command from a linked git worktree only after each matched executable confirms its parsed project-write guard. Missing capability, a failed query or an unreadable response refuses with the CLI update route. Quoted text, heredocs, wrappers and other shell forms are outside this check. Global, read and preview commands pass silently.
# summary: Requires a CLI with project-write protection before advising on plain kendex writes in linked worktrees. Older executables must be updated.
# safety: Reads the hook payload and git checkout paths. Queries each matched executable with --worktree-project-write-capability; a supporting CLI answers before bootstrap writes. Refuses missing payload tools, unreadable or invalid payloads, invalid working-directory values, missing CLI capability and failed context output. A supported executable retains unavailable advisories for a missing git or a failed git check.
# timeout: 10
# ---

set -euo pipefail

refuse() {
  printf 'block-worktree-refresh: %s=%s\n' "$1" "$2" >&2
  [ -z "${3:-}" ] || printf '%s\n' "$3" >&2
  exit 2
}

notice() { # KEY VALUE [CAUSE]
  local text context shape
  require_guard
  text="block-worktree-refresh: $1=$2
The CLI checks the actual project destination before any write. Run from that checkout for a project change."
  [ -z "${3:-}" ] || text="$text
$3"
  printf '%s\n' "$text" >&2
  case "${BASH_SOURCE[0]}" in
    */.github/hooks/*) shape='{additionalContext: $text}' ;;
    *)
      if [ -f "${BASH_SOURCE[0]%.sh}.json" ]; then
        shape='{additionalContext: $text}'
      else
        shape='{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $text}}'
      fi
      ;;
  esac
  context=$(jq -nc --arg text "$text" "$shape" 2>&1) || refuse notice unwritten "$context"
  printf '%s\n' "$context"
  exit 0
}

require_guard() {
  local executable
  for executable in "${EXECUTABLES[@]}"; do
    # The CLI owns target checks. A catalog refresh can reach an executable
    # that predates them, so an advisory needs its documented fixed response.
    if ! (cd -- "$CWD" && "$executable" --worktree-project-write-capability) 2>/dev/null |
      jq -e -s 'length == 1 and .[0] == {worktree_project_write_guard: 1}' >/dev/null 2>&1; then
      printf 'block-worktree-refresh: cli-update-required=%s; route=update\n' "$executable" >&2
      exit 2
    fi
  done
}

MISSING=""
for dependency in jq cat; do
  command -v "$dependency" >/dev/null 2>&1 || MISSING="$MISSING,$dependency"
done
[ -z "$MISSING" ] || refuse missing-tools "${MISSING#,}"
INPUT=$(cat 2>&1) || refuse payload unreadable "$INPUT"
case "$INPUT" in
  *[![:space:]]*) ;;
  *) refuse payload empty ;;
esac
COMMAND=$(printf '%s' "$INPUT" | jq -r '
  def copilot: .toolArgs
    | if . == null then null elif type == "string" then fromjson else . end
    | if . == null then null elif type == "object" then .command else error end;
  if .tool_input.command != null then .tool_input.command
  elif .command != null then .command
  elif copilot != null then copilot
  else "" end
  | if type == "string" then . else error end' 2>/dev/null) || refuse payload invalid-json

# This advisory accepts only plain text. The CLI evaluates shell forms
# after the shell has selected the command, arguments and directory.
PLAIN='^[[:alnum:]_./:@%=+,[:space:]&|;-]*$'
[[ $COMMAND =~ $PLAIN ]] || exit 0
COMMAND=${COMMAND//;/$'\n'}
COMMAND=${COMMAND//&/$'\n'}
COMMAND=${COMMAND//|/$'\n'}
WRITE=""
EXECUTABLES=()
while IFS= read -r segment; do
  EXECUTABLE='^[[:space:]]*(([^[:space:]]*/)?kendex)[[:space:]]+([^[:space:]]+)'
  [[ $segment =~ $EXECUTABLE ]] || continue
  executable=${BASH_REMATCH[1]}
  verb=${BASH_REMATCH[3]}
  tail=${segment#*kendex}
  read_only='(^|[[:space:]])(--help|-h|--plan)([[:space:]]|$)'
  [[ ! $tail =~ $read_only ]] || continue
  scope='(^|[[:space:]])--scope([[:space:]]+|=)([^[:space:]]+)'
  global='(^|[[:space:]])(-g|--global)([[:space:]]|$)'
  if [[ $tail =~ $scope ]]; then
    [ "${BASH_REMATCH[3]}" != global ] || continue
  elif [[ $tail =~ $global ]]; then
    continue
  fi
  case "$verb" in
    refresh|apply|add|remove|pin|fork|adopt|drift-hook) ;;
    updates)
      [[ $tail =~ (^|[[:space:]])--apply([[:space:]]|$) ]] || continue ;;
    update-pi)
      [[ ! $tail =~ (^|[[:space:]])(--check|-c)([[:space:]]|$) ]] || continue ;;
    source)
      [[ $tail =~ (^|[[:space:]])(add|remove|enable|disable)([[:space:]]|$) ]] || continue ;;
    marketplace)
      [[ $tail =~ (^|[[:space:]])(subscribe|unsubscribe)([[:space:]]|$) ]] || continue ;;
    *) continue ;;
  esac
  [ -n "$WRITE" ] || WRITE=$verb
  EXECUTABLES+=("$executable")
done <<<"$COMMAND"
[ -n "$WRITE" ] || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '
  if .tool_input.workdir != null then .tool_input.workdir
  elif .tool_input.cwd != null then .tool_input.cwd
  elif .cwd != null then .cwd
  else "" end
  | if type == "string" then . else error end' 2>/dev/null) || refuse payload invalid-cwd
[ -n "$CWD" ] || CWD=$PWD
command -v git >/dev/null 2>&1 || notice unavailable git
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES
export LC_ALL=C
if ! DIRS=$(git -C "$CWD" rev-parse --git-dir --git-common-dir 2>&1); then
  case "$DIRS" in
    *'not a git repository (or any'*) exit 0 ;;
    *) notice unavailable git "$DIRS" ;;
  esac
fi
resolve() {
  case "$2" in
    /*) (cd -- "$2" 2>&1 && pwd -P) ;;
    *) (cd -- "$1/$2" 2>&1 && pwd -P) ;;
  esac
}
GIT_DIR=$(resolve "$CWD" "${DIRS%%$'\n'*}") || notice unavailable git "$GIT_DIR"
COMMON_DIR=$(resolve "$CWD" "${DIRS#*$'\n'}") || notice unavailable git "$COMMON_DIR"
[ "$GIT_DIR" != "$COMMON_DIR" ] || exit 0
notice advisory "$WRITE"
