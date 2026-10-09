#!/usr/bin/env bash
# Inputs: block-worktree-refresh.sh and lib/first-line.sh.
# The parsed CLI owns destination refusals. The catalog hook requires its
# installed PATH command's fixed capability protocol before advisory output
# or delegation of a baseline-recognized non-plain writer to the CLI.
# Only one plain bare call can advise. Other plain writer-word matches refuse.
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
printf 'queried\n' >>"$QUERY_LOG"
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
QUERY_LOG="$TMP_ROOT/query.log"
export QUERY_LOG
export GIT_CEILING_DIRECTORIES="$TMP_ROOT"
MAIN="$TMP_ROOT/main"
WT="$TMP_ROOT/linked"
git init -q "$MAIN"
git -C "$MAIN" config gc.auto 0
git -C "$MAIN" config maintenance.auto false
git -C "$MAIN" -c user.name=test -c user.email=test@example.com commit -qm seed --allow-empty
git -C "$MAIN" worktree add -qb lane "$WT"
UNAPPROVED_MARKER="$WT/unapproved-execution"
export UNAPPROVED_MARKER
mkdir -p "$WT/tools" "$WT/aliases" "$WT/hard"
# This edited repository executable is the finding's real producer. Calling
# it before command approval leaves a marker even if the hook later refuses.
cat >"$WT/tools/kendex" <<'CLI'
#!/usr/bin/env bash
printf 'invoked\n' >>"$UNAPPROVED_MARKER"
printf '{"worktree_project_write_guard":1}\n'
CLI
chmod +x "$WT/tools/kendex"
ln -s "$BIN/kendex" "$WT/aliases/kendex"
ln "$BIN/kendex" "$WT/hard/kendex"
assert_eq() {
  if [ "$1" = "$2" ]; then PASS=$((PASS + 1)); printf 'ok %s\n' "$3"
  else FAIL=$((FAIL + 1)); printf 'FAIL %s: expected [%s], got [%s]\n' "$3" "$2" "$1"; fi
  case "$2" in
    'rc=2 first=block-worktree-refresh: refused='*)
      if [ ! -s "$QUERY_LOG" ] && [ ! -e "$UNAPPROVED_MARKER" ]; then
        PASS=$((PASS + 1)); printf 'ok %s no launch\n' "$3"
      else
        FAIL=$((FAIL + 1)); printf 'FAIL %s: refusal launched a command\n' "$3"
      fi
      if [ ! -s "$OUT_FILE" ]; then PASS=$((PASS + 1)); printf 'ok %s no context\n' "$3"
      else FAIL=$((FAIL + 1)); printf 'FAIL %s: refusal added context\n' "$3"; fi
      ;;
  esac
  # A silent tool call must add no session context through stdout.
  if [ "$2" = 'rc=0 first=-' ]; then
    if [ ! -s "$OUT_FILE" ]; then PASS=$((PASS + 1)); printf 'ok %s stdout\n' "$3"
    else FAIL=$((FAIL + 1)); printf 'FAIL %s: stdout is not empty\n' "$3"; fi
  fi
}
run_payload() {
  rc=0
  : >"$QUERY_LOG"
  (cd -- "${HOOK_CWD:-$PWD}" && printf '%s' "$1" | "$BASH_BIN" "$HOOK") >"$OUT_FILE" 2>"$ERR_FILE" || rc=$?
}
run_hook() {
  local payload
  payload=$(jq -nc --arg command "$1" --arg cwd "${CURRENT_CWD:-$WT}" '{cwd:$cwd,tool_input:{command:$command}}')
  run_payload "$payload"
}
. "$TEST_DIR/lib/first-line.sh"
assert_unapproved_not_run() {
  local invoked=no
  [ ! -e "$UNAPPROVED_MARKER" ] || invoked=yes
  assert_eq "$invoked" no 'unapproved executable has no invocation marker'
}

VG_ROW="VG-265 title stays silent|command|0|-|github.sh pr-create --title 'chore(VG-265): CI: adopt the 6-hourly kendex refresh schedule' --body-file tmp/body.md"
DATA_ROWS="$VG_ROW
commit message stays silent|command|0|-|git commit -m 'adopt the kendex refresh schedule'
issue title stays silent|command|0|-|linear.sh issues create --title 'kendex refresh'
quoted data stays silent|command|0|-|printf '%s' 'kendex refresh'
heredoc data stays silent|command|0|-|cat \0074\0074'EOF'\nkendex refresh\nEOF
quoted shell execution belongs to CLI|command|0|-|bash -c 'kendex refresh'"
first_table "$DATA_ROWS"
QUOTED_ROW='quoted writer belongs to guarded CLI|command|0|-|kendex "refresh"'
first_table "$QUOTED_ROW"
assert_eq "$(cat "$QUERY_LOG")" queried 'quoted writer asks trusted PATH capability'
first_table 'plain refresh is an advisory|command|0|block-worktree-refresh: advisory=refresh|kendex refresh
plain next command refuses|command|2|block-worktree-refresh: refused=refresh|git status && kendex refresh
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
first_table "plain executable path refuses|command|2|block-worktree-refresh: refused=apply|$BIN/kendex apply"

for mode in old failed empty unreadable wrong multiple stderr; do
  export CAPABILITY_MODE=$mode
  # Include every file, directory and link under the project and portable home.
  tar -cf "$TMP_ROOT/before.tar" -C "$TMP_ROOT" main linked home
  first_table "$mode capability refuses|command|2|block-worktree-refresh: cli-update-required=$BIN/kendex; route=update|kendex refresh"
  first_table "$mode quoted writer refuses|command|2|block-worktree-refresh: cli-update-required=$BIN/kendex; route=update|kendex \"refresh\""
  assert_eq "$(awk 'END {print NR}' "$ERR_FILE")" 1 "$mode refusal has one update line"
  [ ! -s "$OUT_FILE" ] && output=empty || output=present
  assert_eq "$output" empty "$mode refusal has no context"
  tar -cf "$TMP_ROOT/after.tar" -C "$TMP_ROOT" main linked home
  if cmp -s "$TMP_ROOT/before.tar" "$TMP_ROOT/after.tar"; then unchanged=yes; else unchanged=no; fi
  assert_eq "$unchanged" yes "$mode refusal preserves complete fixture"
done
# Baseline writer words in data require the same capability on an older CLI.
export CAPABILITY_MODE=old
silent='|command|0|-|'
update="|command|2|block-worktree-refresh: cli-update-required=$BIN/kendex; route=update|"
first_table "${DATA_ROWS//$silent/$update}"
first_table 'older global stays silent|command|0|-|kendex refresh --scope global
older read stays silent|command|0|-|kendex verify
older preview stays silent|command|0|-|kendex apply --plan
older quoted non-writer stays silent|command|0|-|printf "%s" "kendex verify"'
export CAPABILITY_MODE=supported
REFUSED_ROWS="PATH export compound refuses|command|2|block-worktree-refresh: refused=refresh|export PATH=$OLD_BIN; kendex refresh
PATH assignment refuses|command|2|block-worktree-refresh: refused=refresh|PATH=$OLD_BIN kendex refresh
env PATH prefix refuses|command|2|block-worktree-refresh: refused=refresh|env PATH=$OLD_BIN kendex refresh
other assignment refuses|command|2|block-worktree-refresh: refused=refresh|FOO=1 kendex refresh
wrapper refuses|command|2|block-worktree-refresh: refused=refresh|env FOO=1 kendex refresh
earlier command refuses|command|2|block-worktree-refresh: refused=refresh|true && kendex refresh
later command refuses|command|2|block-worktree-refresh: refused=refresh|kendex refresh; true
pipeline refuses|command|2|block-worktree-refresh: refused=refresh|kendex refresh | cat
background refuses|command|2|block-worktree-refresh: refused=refresh|kendex refresh &
newline refuses|command|2|block-worktree-refresh: refused=refresh|true\nkendex refresh
plain argument retains baseline refusal|command|2|block-worktree-refresh: refused=refresh|printf kendex refresh
same absolute file refuses|command|2|block-worktree-refresh: refused=refresh|$BIN/kendex refresh
same symbolic file refuses|command|2|block-worktree-refresh: refused=refresh|aliases/kendex refresh
same hard-linked file refuses|command|2|block-worktree-refresh: refused=refresh|hard/kendex refresh
unknown absolute file refuses|command|2|block-worktree-refresh: refused=refresh|$WT/tools/kendex refresh
unknown relative file refuses|command|2|block-worktree-refresh: refused=refresh|tools/kendex refresh
supported first cannot hide later writer|command|2|block-worktree-refresh: refused=refresh|kendex refresh && tools/kendex apply
earlier read cannot hide later writer|command|2|block-worktree-refresh: refused=apply|kendex verify && tools/kendex apply
missing executable refuses without launch|command|2|block-worktree-refresh: refused=refresh|$TMP_ROOT/missing/kendex refresh"
tar -cf "$TMP_ROOT/before.tar" -C "$TMP_ROOT" main linked home
first_table "$REFUSED_ROWS"
assert_unapproved_not_run
tar -cf "$TMP_ROOT/after.tar" -C "$TMP_ROOT" main linked home
if cmp -s "$TMP_ROOT/before.tar" "$TMP_ROOT/after.tar"; then unchanged=yes; else unchanged=no; fi
assert_eq "$unchanged" yes 'plain fallback refusals preserve complete fixture'
first_table "assignment global stays silent|command|0|-|PATH=$OLD_BIN kendex refresh --global
env global stays silent|command|0|-|env PATH=$OLD_BIN kendex refresh --global
wrapper read stays silent|command|0|-|env FOO=1 kendex verify
wrapper preview stays silent|command|0|-|env FOO=1 kendex apply --plan"
supported_path=$PATH
export PATH="$OLD_BIN:$PATH"
first_table "other path refuses before trusted query|command|2|block-worktree-refresh: refused=refresh|$BIN/kendex refresh
old trusted command requires update|command|2|block-worktree-refresh: cli-update-required=$OLD_BIN/kendex; route=update|kendex refresh"
export PATH=$supported_path

if [ -n "${KENDEX_UNDER_TEST:-}" ]; then
  # The build receipt binds this actual executable to the changed CLI tree.
  mkdir -p "$TMP_ROOT/current"
  ln -s "$KENDEX_UNDER_TEST" "$TMP_ROOT/current/kendex"
  export PATH="$TMP_ROOT/current:$PATH"
  tar -cf "$TMP_ROOT/before.tar" -C "$TMP_ROOT" main linked home
  first_table "actual current CLI stays advisory|command|0|block-worktree-refresh: advisory=refresh|kendex refresh"
  tar -cf "$TMP_ROOT/after.tar" -C "$TMP_ROOT" main linked home
  if cmp -s "$TMP_ROOT/before.tar" "$TMP_ROOT/after.tar"; then unchanged=yes; else unchanged=no; fi
  assert_eq "$unchanged" yes 'actual capability query preserves complete fixture'
  export PATH=$supported_path
fi

run_hook 'kendex refresh'
context=$(jq -r '(.hookSpecificOutput.additionalContext // .additionalContext) | split("\n")[0]' "$OUT_FILE")
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
for defect in title advisory capability_old capability_failed capability_unreadable quoted_permissive quoted_word single_call baseline_word unapproved_launch; do
  mutant="$TMP_ROOT/$defect.sh"
  rm -f "$UNAPPROVED_MARKER"
  case "$defect" in
    title)
      awk '/^PLAIN=/ { print "[[ $COMMAND != *--title* ]] || { SINGLE_CALL=yes; WRITE=refresh; notice advisory refresh 2>/dev/null; }"; n++ } {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows=$VG_ROW ;;
    advisory)
      awk '/^notice advisory "\$WRITE"$/ {print ": advisory \"$WRITE\""; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows='plain refresh is an advisory|command|0|block-worktree-refresh: advisory=refresh|kendex refresh' ;;
    capability_*)
      awk '/^  require_guard$/ {print "  : require_guard"; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      export CAPABILITY_MODE=${defect#capability_}
      rows="$CAPABILITY_MODE capability refuses|command|2|block-worktree-refresh: cli-update-required=$BIN/kendex; route=update|kendex refresh" ;;
    quoted_permissive)
      awk '/^  \[ -z "\$FOUND" \] \|\| require_capability$/ {sub(/require_capability$/, ": require_capability"); n++} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      export CAPABILITY_MODE=old
      rows="old quoted writer refuses|command|2|block-worktree-refresh: cli-update-required=$BIN/kendex; route=update|kendex \"refresh\"" ;;
    quoted_word)
      awk '/^    word=\$\{word#\[/ {print "    : \"$word\""; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      export CAPABILITY_MODE=old
      rows="old quoted writer refuses|command|2|block-worktree-refresh: cli-update-required=$BIN/kendex; route=update|kendex \"refresh\"" ;;
    single_call)
      awk '/^  \[ "\$SINGLE_CALL" = yes \]/ {sub(/\[ "\$SINGLE_CALL" = yes \]/, ": \"$SINGLE_CALL\" = yes"); n++} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows=$REFUSED_ROWS ;;
    baseline_word)
      awk '/^KENDEX_RE=/ {print "KENDEX_RE=\047^kendex([[:space:]]|$)\047"; n++; next} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows="PATH assignment refuses|command|2|block-worktree-refresh: refused=refresh|PATH=$OLD_BIN kendex refresh" ;;
    unapproved_launch)
      awk '/^  \[ "\$SINGLE_CALL" = yes \]/ {print "  \"$CWD/tools/kendex\" --worktree-project-write-capability >/dev/null 2>&1"; n++} {print} END {if(n!=1) exit 2}' "$HOOK" >"$mutant"
      rows="unknown relative file refuses|command|2|block-worktree-refresh: refused=refresh|tools/kendex refresh" ;;

  esac
  original=$HOOK saved_pass=$PASS saved_fail=$FAIL
  HOOK=$mutant PASS=0 FAIL=0
  first_table "$rows" >"$TMP_ROOT/$defect.result"
  if [ "$defect" = unapproved_launch ]; then
    assert_unapproved_not_run >>"$TMP_ROOT/$defect.result"
  fi
  failed=$FAIL
  HOOK=$original PASS=$saved_pass FAIL=$saved_fail
  [ "$failed" -gt 0 ] && status=red || status=green
  assert_eq "$status" red "$defect defect turns its assertion red"
  export CAPABILITY_MODE=supported
done
rm -f "$UNAPPROVED_MARKER"
printf 'block-worktree-refresh: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
