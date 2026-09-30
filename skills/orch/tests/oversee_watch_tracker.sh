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
  OUT="$(run_watch "$@" -- --max-loops 1 --since 2026-08-15T09:00:00Z --state "$STUB_DIR/state.json" 2>"$ERR")" && RC=0 || RC=$?
}
world tracker_interval
# Linear's complete safe list includes descriptions and completed history.
# Keep the interval case's triage and owed items inside a full team payload.
LARGE_TRACKER="$TMP_ROOT/tracker-large.json"
jq 'map(. + {description: ("Full issue description with requirements and evidence.\n" * 64)})
  + [range(3;2262) | {id: ("KEN-" + tostring), state: "Done", priority: 3,
      created_at: "2026-08-01T00:00:00Z",
      description: ("Full issue description with requirements and evidence.\n" * 64)}]' \
  "$STUB_DIR/tracker.out" >"$LARGE_TRACKER"
cp -- "$LARGE_TRACKER" "$STUB_DIR/tracker.out"
tracker_pass
assert_eq "$RC" 0 'initial shared tracker read succeeds' "$ERR"
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 1 'triage and owed share one live list' "$ERR"
assert_contains "$OUT" 'owed KEN-1 state=in-review' 'owed includes items older than the triage floor' "$ERR"
assert_eq "$(jq -s '.[0].issues == .[1] and (.[0].issues | length) == 2261' \
  "$CASE_REPO_ROOT/.cache/linear/watch-team.json" "$STUB_DIR/tracker.out")" true \
  'large snapshot preserves the complete team list and descriptions' "$ERR"
printf '[{"id":"KEN-3","state":"In Progress","priority":2,"created_at":"2026-08-15T10:00:00Z"}]\n' >"$STUB_DIR/tracker.out"
printf '1786960800\n' >"$STUB_DIR/now.epoch"
tracker_pass
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 1 'between intervals the watch spends no request' "$ERR"
assert_contains "$OUT" 'owed KEN-1 state=in-review' 'between intervals the watch reads its cached answer' "$ERR"
printf '1786960801\n' >"$STUB_DIR/now.epoch"
tracker_pass
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 2 'at the interval boundary the watch lists once' "$ERR"
assert_contains "$OUT" 'EVENT triage KEN-3' 'the next live list supplies new triage items' "$ERR"
printf '[{"id":"FLEET-1","state":"In Review","priority":2,"created_at":"2026-08-15T10:00:00Z"}]\n' >"$STUB_DIR/tracker.out"
tracker_pass LINEAR_TEAM=fleet
assert_eq "$RC" 0 'a changed team succeeds on a fresh snapshot' "$ERR"
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 3 'a changed team makes one new live request' "$ERR"
assert_eq "$(cat "$STUB_DIR/tracker.args")" 'issues list --team fleet --max --require-complete --format=safe' \
  'the new request selects the changed team' "$ERR"
assert_contains "$OUT" 'EVENT triage FLEET-1' 'triage selects the new team results' "$ERR"
printf '{"triaged":[{"issue":"FLEET-1","verdict":"kept"}]}\n' >"$STUB_DIR/oversee-state.json"
tracker_pass LINEAR_TEAM=fleet
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 3 'owed reuses the changed team snapshot' "$ERR"
assert_contains "$OUT" 'owed FLEET-1 state=in-review' 'owed selects the new team results' "$ERR"
assert_not_contains "$OUT" 'KEN-3' 'the changed team does not reuse the previous team results' "$ERR"
assert_eq "$(jq -c '[.team, [.issues[].id]]' "$CASE_REPO_ROOT/.cache/linear/watch-team.json")" \
  '["fleet",["FLEET-1"]]' 'the shared snapshot now belongs to the changed team' "$ERR"
printf '{}\n' >"$CASE_REPO_ROOT/.cache/linear/watch-team.json"
tracker_pass
assert_eq "$RC" 2 'corrupt snapshot refuses rather than hiding tracker work' "$ERR"

world tracker_explicit_interval
tracker_pass ORCH_WATCH_TRACKER_INTERVAL=1
printf '1786957202\n' >"$STUB_DIR/now.epoch"
tracker_pass ORCH_WATCH_TRACKER_INTERVAL=1
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 2 \
  'an explicit nondefault interval still controls refresh' "$ERR"

world tracker_invalid_interval
ERR="$STUB_DIR/invalid.err"
OUT="$(run_watch ORCH_WATCH_TRACKER_INTERVAL=0 -- --max-loops 1 2>"$ERR")" && RC=0 || RC=$?
assert_eq "$RC" 2 'zero tracker interval is refused' "$ERR"
assert_contains "$(cat "$ERR")" 'tracker-interval-invalid' 'invalid interval names its setting' "$ERR"

world tracker_incomplete
tracker_pass
SNAPSHOT="$(cat "$CASE_REPO_ROOT/.cache/linear/watch-team.json")"
printf '1786960801\n' >"$STUB_DIR/now.epoch"
printf '1\n' >"$STUB_DIR/tracker.rc"
printf 'issues-list-incomplete: pages=200 cap=200\n' >"$STUB_DIR/tracker.err"
tracker_pass
assert_eq "$RC" 2 'incomplete live listing refuses the watch pass' "$ERR"
assert_contains "$(cat "$ERR")" 'tracker-list-failed' 'the watch exposes the failed list' "$ERR"
assert_not_contains "$OUT" 'EVENT triage' 'incomplete listing produces no triage event' "$ERR"
assert_eq "$(cat "$CASE_REPO_ROOT/.cache/linear/watch-team.json")" "$SNAPSHOT" \
  'incomplete listing preserves the prior complete snapshot' "$ERR"

# Must-fail: remove only the strict listing option. The argv contract then
# permits the producer's successful partial result again.
MUTANT="$(mutant_scripts tracker-complete-mutant/orch lib/watch-tracker.sh)/oversee-watch"
ln -s "$REPO_ROOT/skills/github" "$TMP_ROOT/tracker-complete-mutant/github"
mutate_file "${MUTANT%/*}/lib/watch-tracker.sh" '--max --require-complete --format=safe' '--max --format=safe'
world tracker_complete_control
WATCH_BIN="$MUTANT" tracker_pass LINEAR_TEAM=fleet
assert_eq "$(cat "$STUB_DIR/tracker.args")" 'issues list --team fleet --max --format=safe' \
  'control: removing completeness makes the strict argv pin red' "$ERR"

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

# Must-fail: disable only team identity while retaining snapshot freshness.
MUTANT="$(mutant_scripts tracker-team-mutant/orch lib/watch-tracker.sh)/oversee-watch"
ln -s "$REPO_ROOT/skills/github" "$TMP_ROOT/tracker-team-mutant/github"
mutate_file "${MUTANT%/*}/lib/watch-tracker.sh" \
  'elif .team != $team then 0 else .read_at end' 'elif false then 0 else .read_at end'
world tracker_team_control
WATCH_BIN="$MUTANT" tracker_pass
printf '[{"id":"FLEET-1","state":"In Review","priority":2,"created_at":"2026-08-15T10:00:00Z"}]\n' >"$STUB_DIR/tracker.out"
WATCH_BIN="$MUTANT" tracker_pass LINEAR_TEAM=fleet
assert_eq "$(wc -l <"$STUB_DIR/tracker.calls" | tr -d ' ')" 1 \
  'control: disabled team match makes the new-request pin red' "$ERR"
assert_contains "$OUT" 'owed KEN-1 state=in-review' \
  'control: disabled team match selects the previous team instead' "$ERR"
assert_not_contains "$OUT" 'FLEET-1' 'control: disabled team match loses the selected team results' "$ERR"

# Must-fail: move only snapshot serialization back to argv. The complete
# Linear team payload exceeds the host's argument limit before jq starts.
MUTANT="$(mutant_scripts tracker-payload-mutant/orch lib/watch-tracker.sh)/oversee-watch"
ln -s "$REPO_ROOT/skills/github" "$TMP_ROOT/tracker-payload-mutant/github"
mutate_file "${MUTANT%/*}/lib/watch-tracker.sh" \
  'jq -c --arg team "$LINEAR_TEAM" --argjson now "$now"' \
  'jq -cn --arg team "$LINEAR_TEAM" --argjson now "$now" --argjson issues "$out"'
mutate_file "${MUTANT%/*}/lib/watch-tracker.sh" \
  '{team: $team, read_at: $now, issues: .}' '{team: $team, read_at: $now, issues: $issues}'
world tracker_payload_control
cp -- "$LARGE_TRACKER" "$STUB_DIR/tracker.out"
WATCH_BIN="$MUTANT" tracker_pass
assert_eq "$RC" 2 'control: argv serialization makes the large-payload success pin red' "$ERR"

# Must-fail: disable only the positive interval grammar.
MUTANT="$(mutant_scripts tracker-setting-mutant/orch oversee-watch)/oversee-watch"
ln -s "$REPO_ROOT/skills/github" "$TMP_ROOT/tracker-setting-mutant/github"
mutate_file "$MUTANT" '[[ "$TRACKER_INTERVAL" =~ ^[1-9][0-9]{0,8}$ ]]' 'true'
world tracker_setting_control
OUT="$(WATCH_BIN="$MUTANT" run_watch ORCH_WATCH_TRACKER_INTERVAL=0 -- --max-loops 1 2>"$STUB_DIR/err")" && RC=0 || RC=$?
assert_eq "$RC" 0 'control: disabled interval grammar accepts zero' "$STUB_DIR/err"
printf 'pass: %d   fail: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
