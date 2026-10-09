#!/usr/bin/env bash
# ---
# name: block-worktree-refresh
# event: PreToolUse
# matcher: Bash
# description: Report an early advisory for a plain project-writing kendex command from a linked git worktree only after the installed executable on the hook's PATH confirms its parsed project-write guard. A path-qualified candidate must name that same file; any other candidate refuses with the trusted command route without execution. Missing capability, a failed query or an unreadable response refuses with the CLI update route. Quoted text, heredocs, wrappers and other shell forms are outside this check. Global, read and preview commands pass silently.
# summary: Requires the installed CLI's project-write protection before advising on plain kendex writes in linked worktrees. Other executable paths must name that same file.
# safety: Reads the hook payload, git checkout paths and candidate file identities. Queries only the installed executable resolved by the hook's PATH with --worktree-project-write-capability; a supporting CLI answers before bootstrap writes. Never executes a proposed path. Refuses unreadable or invalid payloads, missing payload tools, invalid working-directory values, other executable identities, missing CLI capability and failed context output. A supported executable retains unavailable advisories for a missing git or a failed git check.
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
  local trusted executable candidate
  trusted=$(type -P kendex) || refuse cli-update-required 'kendex; route=update'
  case "$trusted" in
    /*) ;;
    *) trusted="$PWD/$trusted" ;;
  esac
  for executable in "${EXECUTABLES[@]}"; do
    case "$executable" in
      */*)
        case "$executable" in
          /*) candidate=$executable ;;
          *) candidate="$CWD/$executable" ;;
        esac
        # Claude PreToolUse runs before Bash approval. Candidate identity is a
        # read-only check, never permission to launch the proposed bytes.
        [ "$candidate" -ef "$trusted" ] || refuse cli-untrusted "$executable; route=$trusted"
        ;;
    esac
  done
  # Catalog refresh and executable updates are independent. Only the hook's
  # installed PATH command may supply the guard's documented fixed response.
  if ! "$trusted" --worktree-project-write-capability 2>/dev/null |
    jq -e -s 'length == 1 and .[0] == {worktree_project_write_guard: 1}' >/dev/null 2>&1; then
    refuse cli-update-required "$trusted; route=update"
  fi
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
