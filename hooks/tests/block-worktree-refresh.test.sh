#!/usr/bin/env bash
# Inputs: block-worktree-refresh.sh and lib/first-line.sh.
# The parsed CLI owns destination refusals. The catalog hook requires its
# fixed capability protocol before advisory output or unavailable notices.
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
BIN="$TMP_ROOT/bin"
OLD_BIN="$TMP_ROOT/old"
mkdir -p "$BIN" "$OLD_BIN"
# An older executable rejects the new flag. The other rows exercise the
# capability consumer's status and JSON contracts, rather than CLI internals.
cat >"$BIN/kendex" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" = 1 ] && [ "$1" = --worktree-project-write-capability ] || exit 2
case "${CAPABILITY_MODE:-supported}" in
  supported) printf '{"worktree_project_write_guard":1}\n' ;;
  old) exit 2 ;;
  failed) printf '{"worktree_project_write_guard":1}\n'; exit 7 ;;
  empty) : ;;
  unreadable) printf 'not-json\n' ;;
  wrong) printf '{"worktree_project_write_guard":0}\n' ;;
  multiple) printf '{"worktree_project_write_guard":1}\n{"worktree_project_write_guard":1}\n' ;;
  stderr) printf '{"worktree_project_write_guard":1}\n' >&2 ;;
esac
CLI
printf '#!/usr/bin/env bash\nexit 2\n' >"$OLD_BIN/kendex"
chmod +x "$BIN/kendex" "$OLD_BIN/kendex"
export PATH="$BIN:$PATH"
export CAPABILITY_MODE=supported
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
first_table "plain executable path is an advisory|command|0|block-worktree-refresh: advisory=apply|$BIN/kendex apply"

for mode in old failed empty unreadable wrong multiple stderr; do
  export CAPABILITY_MODE=$mode
  # Include every file, directory and link under the project and portable home.
  tar -cf "$TMP_ROOT/before.tar" -C "$TMP_ROOT" main linked home
  first_table "$mode capability refuses|command|2|block-worktree-refresh: cli-update-required=kendex; route=update|kendex refresh"
  assert_eq "$(awk 'END {print NR}' "$ERR_FILE")" 1 "$mode refusal has one update line"
  [ ! -s "$OUT_FILE" ] && output=empty || output=present
  assert_eq "$output" empty "$mode refusal has no context"
  tar -cf "$TMP_ROOT/after.tar" -C "$TMP_ROOT" main linked home
  if cmp -s "$TMP_ROOT/before.tar" "$TMP_ROOT/after.tar"; then unchanged=yes; else unchanged=no; fi
  assert_eq "$unchanged" yes "$mode refusal preserves complete fixture"
done
# Existing excluded input stays silent even when its executable is older.
export CAPABILITY_MODE=old
first_table "$DATA_ROWS"
first_table 'older global stays silent|command|0|-|kendex refresh --scope global
older read stays silent|command|0|-|kendex verify
older preview stays silent|command|0|-|kendex apply --plan'
export CAPABILITY_MODE=supported
first_table "supported first cannot hide older second|command|2|block-worktree-refresh: cli-update-required=$OLD_BIN/kendex; route=update|$BIN/kendex refresh && $OLD_BIN/kendex apply
missing executable refuses|command|2|block-worktree-refresh: cli-update-required=$TMP_ROOT/missing/kendex; route=update|$TMP_ROOT/missing/kendex refresh"
supported_path=$PATH
export PATH="$OLD_BIN:$PATH"
first_table "selected path beats older PATH command|command|0|block-worktree-refresh: advisory=refresh|$BIN/kendex refresh"
export PATH=$supported_path

if [ -n "${KENDEX_UNDER_TEST:-}" ]; then
  # The build receipt binds this actual executable to the changed CLI tree.
  mkdir -p "$TMP_ROOT/current"
  ln -s "$KENDEX_UNDER_TEST" "$TMP_ROOT/current/kendex"
  tar -cf "$TMP_ROOT/before.tar" -C "$TMP_ROOT" main linked home
  first_table "actual current CLI stays advisory|command|0|block-worktree-refresh: advisory=refresh|$TMP_ROOT/current/kendex refresh"
  tar -cf "$TMP_ROOT/after.tar" -C "$TMP_ROOT" main linked home
  if cmp -s "$TMP_ROOT/before.tar" "$TMP_ROOT/after.tar"; then unchanged=yes; else unchanged=no; fi
  assert_eq "$unchanged" yes 'actual capability query preserves complete fixture'
fi

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
for defect in title executable advisory capability first_only; do
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
    capability)
      awk '/^  require_guard$/ {print "  : require_guard"; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      export CAPABILITY_MODE=old
      rows='old capability refuses|command|2|block-worktree-refresh: cli-update-required=kendex; route=update|kendex refresh' ;;
    first_only)
      awk '/^  EXECUTABLES\+=/ {print; print "  break"; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows="supported first cannot hide older second|command|2|block-worktree-refresh: cli-update-required=$OLD_BIN/kendex; route=update|$BIN/kendex refresh && $OLD_BIN/kendex apply" ;;
  esac
  original=$HOOK saved_pass=$PASS saved_fail=$FAIL
  HOOK=$mutant PASS=0 FAIL=0
  first_table "$rows" >"$TMP_ROOT/$defect.result"
  failed=$FAIL
  HOOK=$original PASS=$saved_pass FAIL=$saved_fail
  [ "$failed" -gt 0 ] && status=red || status=green
  assert_eq "$status" red "$defect defect turns its assertion red"
  export CAPABILITY_MODE=supported
done
printf 'block-worktree-refresh: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
