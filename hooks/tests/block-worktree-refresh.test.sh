#!/usr/bin/env bash
# Inputs: block-worktree-refresh.sh and lib/first-line.sh.
# The parsed CLI owns refusals. This suite checks only plain-command
# advisories, silent data and keyed payload failures.
set -euo pipefail
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_UNDER_TEST:-$(cd "$TEST_DIR/.." && pwd)/block-worktree-refresh.sh}"
PASS=0 FAIL=0
TMP_ROOT="$(mktemp -d)" || { echo 'block-worktree-refresh: scratch=mktemp-failed' >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo 'block-worktree-refresh: scratch=not-a-directory' >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo 'block-worktree-refresh: scratch=resolve-failed' >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
ERR_FILE="$TMP_ROOT/stderr"
OUT_FILE="$TMP_ROOT/stdout"
BASH_BIN="$(command -v bash)"
export HOME="$TMP_ROOT/home"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$TMP_ROOT"
MAIN="$TMP_ROOT/main"
WT="$TMP_ROOT/linked"
git init -q "$MAIN"
git -C "$MAIN" config gc.auto 0
git -C "$MAIN" config maintenance.auto false
git -C "$MAIN" -c user.name=test -c user.email=test@example.com commit -qm seed --allow-empty
git -C "$MAIN" worktree add -qb lane "$WT"
assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS + 1)); printf 'ok %s\n' "$3"
  else FAIL=$((FAIL + 1)); printf 'FAIL %s: expected [%s], got [%s]\n' "$3" "$2" "$1"; fi
  # A silent tool call must add no session context through stdout.
  if [ "$2" = 'rc=0 first=-' ]; then
    if [ ! -s "$OUT_FILE" ]; then PASS=$((PASS + 1)); printf 'ok %s stdout\n' "$3"
    else FAIL=$((FAIL + 1)); printf 'FAIL %s: stdout is not empty\n' "$3"; fi
  fi
}
run_payload() {
  rc=0
  printf '%s' "$1" | "$BASH_BIN" "$HOOK" >"$OUT_FILE" 2>"$ERR_FILE" || rc=$?
}
run_hook() {
  local payload
  payload=$(jq -nc --arg command "$1" --arg cwd "${CURRENT_CWD:-$WT}" '{cwd:$cwd,tool_input:{command:$command}}')
  run_payload "$payload"
}
. "$TEST_DIR/lib/first-line.sh"

VG_ROW="VG-265 title stays silent|command|0|-|github.sh pr-create --title 'chore(VG-265): CI: adopt the 6-hourly kendex refresh schedule' --body-file tmp/body.md"
DATA_ROWS="$VG_ROW
commit message stays silent|command|0|-|git commit -m 'adopt the kendex refresh schedule'
issue title stays silent|command|0|-|linear.sh issues create --title 'kendex refresh'
quoted data stays silent|command|0|-|printf '%s' 'kendex refresh'
heredoc data stays silent|command|0|-|cat \0074\0074'EOF'\nkendex refresh\nEOF
quoted shell execution belongs to CLI|command|0|-|bash -c 'kendex refresh'
wrapper belongs to CLI|command|0|-|env FOO=1 kendex refresh
plain argument is data|command|0|-|printf kendex refresh"
first_table "$DATA_ROWS"
first_table 'plain refresh is an advisory|command|0|block-worktree-refresh: advisory=refresh|kendex refresh
plain executable path is an advisory|command|0|block-worktree-refresh: advisory=apply|/usr/local/bin/kendex apply
plain next command is an advisory|command|0|block-worktree-refresh: advisory=refresh|git status && kendex refresh
global refresh stays silent|command|0|-|kendex refresh --global
global scope stays silent|command|0|-|kendex refresh --scope global
global equals scope stays silent|command|0|-|kendex refresh --scope=global
scope overrides global|command|0|block-worktree-refresh: advisory=refresh|kendex refresh --global --scope project
read stays silent|command|0|-|kendex verify
preview stays silent|command|0|-|kendex apply --plan
Pi check stays silent|command|0|-|kendex update-pi --check
updates list stays silent|command|0|-|kendex updates
updates apply is an advisory|command|0|block-worktree-refresh: advisory=updates|kendex updates --apply
source list stays silent|command|0|-|kendex source list
source add is an advisory|command|0|block-worktree-refresh: advisory=source|kendex source add catalog ./catalog
subscription is an advisory|command|0|block-worktree-refresh: advisory=marketplace|kendex marketplace subscribe ./catalog
help stays silent|command|0|-|kendex refresh --help
invalid JSON refuses|payload|2|block-worktree-refresh: payload=invalid-json|{
wrong command type refuses|payload|2|block-worktree-refresh: payload=invalid-json|{"command":false}
empty payload refuses|payload|2|block-worktree-refresh: payload=empty|-'

run_hook 'kendex refresh'
context=$(jq -r '.hookSpecificOutput.additionalContext | split("\n")[0]' "$OUT_FILE")
assert_eq "$context" 'block-worktree-refresh: advisory=refresh' 'advisory reaches the session as context'
CURRENT_CWD=$MAIN
first_table 'main checkout stays silent|command|0|-|kendex refresh'
CURRENT_CWD=$WT
for field in workdir cwd; do
  payload=$(jq -nc --arg field "$field" --arg cwd "$MAIN" --arg session "$WT" '{cwd:$session,tool_input:{command:"kendex refresh",($field):$cwd}}')
  run_payload "$payload"
  assert_eq "rc=$rc first=$(first_line)" 'rc=0 first=-' 'tool directory overrides session directory'
done
for shape in object string; do
  payload=$(jq -nc --arg cwd "$WT" --arg shape "$shape" '{cwd:$cwd,toolArgs:({command:"kendex refresh"}|if $shape=="string" then tojson else . end)}')
  run_payload "$payload"
  assert_eq "rc=$rc first=$(first_line)" 'rc=0 first=block-worktree-refresh: advisory=refresh' 'Copilot payload carries the same advisory'
done

# Rerun the same assertions against copies with a planted defect.
for defect in title executable advisory; do
  mutant="$TMP_ROOT/$defect.sh"
  case "$defect" in
    title)
      awk '/^PLAIN=/ { print "[[ $COMMAND != *--title* ]] || notice advisory refresh 2>/dev/null"; n++ } {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows=$VG_ROW ;;
    executable)
      awk '/^  EXECUTABLE=/ {sub(/\^/, ""); n++} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows='plain argument is data|command|0|-|printf kendex refresh' ;;
    advisory)
      awk '/^notice advisory "\$WRITE"$/ {print ": advisory \"$WRITE\""; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows='plain refresh is an advisory|command|0|block-worktree-refresh: advisory=refresh|kendex refresh' ;;
  esac
  original=$HOOK saved_pass=$PASS saved_fail=$FAIL
  HOOK=$mutant PASS=0 FAIL=0
  first_table "$rows" >"$TMP_ROOT/$defect.result"
  failed=$FAIL
  HOOK=$original PASS=$saved_pass FAIL=$saved_fail
  [ "$failed" -gt 0 ] && status=red || status=green
  assert_eq "$status" red "$defect defect turns its assertion red"
done
printf 'block-worktree-refresh: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
