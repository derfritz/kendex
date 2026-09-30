#!/usr/bin/env bash
# The live-list interval is independent of long-pass and mail cadence.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/oversee-watch-harness.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/growth-state.sh"

world() {
  new_case "$1"
  printf '1786957201\n' >"$STUB_DIR/now.epoch"
  printf '{"lanes":[]}\n' >"$STUB_DIR/state.json"
  printf '{"triaged":[{"issue":"KEN-2","verdict":"kept"}]}\n' >"$STUB_DIR/oversee-state.json"
  printf '[{"id":"KEN-1","state":"In Review","priority":2,"created_at":"2026-08-01T00:00:00Z"},{"id":"KEN-2","state":"Backlog","priority":3,"created_at":"2026-08-15T10:00:00Z"}]\n' >"$STUB_DIR/tracker.out"
}
tracker_pass() {
  ERR="$STUB_DIR/err"
  OUT="$(run_watch -- --max-loops 1 --since 2026-08-15T09:00:00Z --state "$STUB_DIR/state.json" 2>"$ERR")" && RC=0 || RC=$?
}
world tracker_interval
tracker_pass
assert_eq "$RC" 0 'initial shared tracker read succeeds' "$ERR"
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 1 'triage and owed share one live list' "$ERR"
assert_contains "$OUT" 'owed KEN-1 state=in-review' 'owed includes items older than the triage floor' "$ERR"
printf '[{"id":"KEN-3","state":"In Progress","priority":2,"created_at":"2026-08-15T10:00:00Z"}]\n' >"$STUB_DIR/tracker.out"
printf '1786960800\n' >"$STUB_DIR/now.epoch"
tracker_pass
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 1 'between intervals the watch spends no request' "$ERR"
assert_contains "$OUT" 'owed KEN-1 state=in-review' 'between intervals the watch reads its cached answer' "$ERR"
printf '1786960801\n' >"$STUB_DIR/now.epoch"
tracker_pass
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 2 'at the interval boundary the watch lists once' "$ERR"
assert_contains "$OUT" 'EVENT triage KEN-3' 'the next live list supplies new triage items' "$ERR"
printf '{}\n' >"$CASE_REPO_ROOT/.cache/linear/watch-team.json"
tracker_pass
assert_eq "$RC" 2 'corrupt snapshot refuses rather than hiding tracker work' "$ERR"

world tracker_invalid_interval
ERR="$STUB_DIR/invalid.err"
OUT="$(run_watch ORCH_WATCH_TRACKER_INTERVAL=0 -- --max-loops 1 2>"$ERR")" && RC=0 || RC=$?
assert_eq "$RC" 2 'zero tracker interval is refused' "$ERR"
assert_contains "$(cat "$ERR")" 'tracker-interval-invalid' 'invalid interval names its setting' "$ERR"

# Must-fail: keep the snapshot read but disable its age branch. The same
# repeated pass now makes a live request instead of satisfying the count pin.
MUTANT="$(mutant_scripts tracker-mutant/orch lib/watch-tracker.sh)/oversee-watch"
ln -s "$REPO_ROOT/skills/github" "$TMP_ROOT/tracker-mutant/github"
mutate_file "${MUTANT%/*}/lib/watch-tracker.sh" \
  'if (( now >= stamp && now - stamp < TRACKER_INTERVAL )); then' 'if false; then'
world tracker_control
WATCH_BIN="$MUTANT" tracker_pass
WATCH_BIN="$MUTANT" tracker_pass
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 4 'control: disabling cache freshness makes the no-request pin red' "$ERR"

# Must-fail: disable only the positive interval grammar.
MUTANT="$(mutant_scripts tracker-setting-mutant/orch oversee-watch)/oversee-watch"
ln -s "$REPO_ROOT/skills/github" "$TMP_ROOT/tracker-setting-mutant/github"
mutate_file "$MUTANT" '[[ "$TRACKER_INTERVAL" =~ ^[1-9][0-9]{0,8}$ ]]' 'true'
world tracker_setting_control
OUT="$(WATCH_BIN="$MUTANT" run_watch ORCH_WATCH_TRACKER_INTERVAL=0 -- --max-loops 1 2>"$STUB_DIR/err")" && RC=0 || RC=$?
assert_eq "$RC" 0 'control: disabled interval grammar accepts zero' "$STUB_DIR/err"
printf 'pass: %d   fail: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
