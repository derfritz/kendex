#!/usr/bin/env bash
# Tests for the Copilot session record: `copilot-statusline`, the statusLine
# command a Copilot lane runs, and lib/copilot-session.sh, the one adapter
# every reader goes through. The writer persists the exact JSON the CLI hands
# it, bound to the session and the account; the readers answer with a record
# only where every binding agrees and read anything else as unmeasured. One
# case per binding, one asserted row per shape; the must-fail controls at the
# end mutate a private copy of the library and of the script, never the
# shipped ones.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-env.sh"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)/scripts"
STATUSLINE="$SCRIPTS_DIR/copilot-statusline"
# shellcheck source=lib/assertions.sh
source "$TEST_DIR/lib/assertions.sh"
# mutant_scripts and mutate_file, the two halves of the controls below.
# shellcheck source=lib/growth-state.sh
source "$TEST_DIR/lib/growth-state.sh"
# The library under test, sourced into this shell: each reader is a function,
# and a call to it is the smallest surface that can fail.
# shellcheck source=../scripts/lib/copilot-session.sh
source "$SCRIPTS_DIR/lib/copilot-session.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
# Above pid_max on every platform this runs on (2^22 on Linux, 99999 on
# macOS): a pane whose shell provably runs nothing, and sits on no process's
# parent chain, where pid 1 sits on every one.
DEAD_PID=2147483647

# The session JSON as Copilot 1.0.88 hands its statusLine command, LOCAL to
# that build; every field the readers act on is here.
session_json() { # SESSION TRANSCRIPT TOKENS [ALLOW_ALL]
  jq -nc --arg s "$1" --arg t "$2" --argjson n "$3" --argjson a "${4:-true}" \
    '{session_id: $s, transcript_path: $t, model: {id: "claude-fable-5.1"},
      context_window: {used_percentage: ($n / 10000), current_context_tokens: $n, context_window_size: 1000000},
      ai_used: {total_nano_aiu: 258110000000}, cost: {total_premium_requests: 0}, allow_all_enabled: $a}'
}

RC=0; OUT=""; ERR=""
# The payload is an argument fed through a here-string, never piped in: a
# pipeline would run this in a subshell and every assignment here would be
# lost to the row that reads it.
run_statusline() { # JSON HOME [SCRIPT]
  RC=0
  OUT="$(cd "$TMP_ROOT" && COPILOT_HOME="$2" "${3:-$STATUSLINE}" 2>"$TMP_ROOT/err" <<<"$1")" || RC=$?
  ERR="$(head -n 1 "$TMP_ROOT/err")"
}

echo "=== copilot-session ==="

H="$TMP_ROOT/.1copilot"
mkdir -p "$H"
run_statusline "$(session_json abc-1 /t/session-state/abc-1/events.jsonl 416000)" "$H"
assert_eq "$RC|$OUT|$ERR" "0|claude-fable-5.1 42% ctx 258.11 AIC|" \
  "the writer persists the session and prints the footer from the same fields"
RECORD="$H/lane-status/abc-1.json"
assert_eq "$(jq -r '[.session_id, .transcript_path, .copilot_home, (.pid | type), (.written_at | type), .status.model.id, .status.context_window.current_context_tokens] | join(" ")' "$RECORD")" \
  "abc-1 /t/session-state/abc-1/events.jsonl $H number number claude-fable-5.1 416000" \
  "the record binds the session id, transcript, account, pid and time beside the CLI's own object"
assert_eq "$(jq -c '.status' "$RECORD")" "$(session_json abc-1 /t/session-state/abc-1/events.jsonl 416000)" \
  "the CLI's object is persisted exactly as received"
assert_eq "$(stat -c %a "$RECORD" 2>/dev/null || stat -f %Lp "$RECORD")" "600" "the record is private to the account's owner"

run_statusline '{"model":{"id":"m"}}' "$H"
assert_eq "$RC|$ERR" "1|copilot-statusline: payload=unbound" "a payload naming no session is refused, and no record written"
run_statusline 'not json' "$H"
assert_eq "$RC|$ERR" "1|copilot-statusline: payload=invalid-json" "a payload that is not JSON is refused"
run_statusline '{"session_id":"../escape"}' "$H"
assert_eq "$RC|$ERR|$(ls "$H/lane-status" | tr '\n' ',')" "1|copilot-statusline: payload=unbound|abc-1.json," \
  "a session id outside its alphabet names no record path and is refused"
run_statusline '{"session_id":"s2"}' "$H"
assert_eq "$RC|$(jq -c '.status.context_window' "$H/lane-status/s2.json")" "0|null" \
  "a session naming no context is recorded with none, never with a figure"

# The readers, against the record the writer left. Every reader takes its
# clock as an argument, and this suite never reads the wall clock: NOW is the
# stamp of the record written last, re-read after each write, so a second
# that ticks between a write and a row moves no bound, and the age rows
# count from the stamp the bound is measured against.
stamp_of() { jq -r '.written_at' "$1"; } # RECORD_PATH
NOW="$(stamp_of "$RECORD")"
read_status() { # HOME SESSION [TRANSCRIPT] [NOW]
  local rc=0
  copilot_session_read "$@" || rc=$?
  printf '%s|%s' "$rc" "${COPILOT_SESSION_REASON:-ok}"
}
assert_eq "$(read_status "$H" abc-1 /t/session-state/abc-1/events.jsonl "$NOW")" "0|ok" "a record bound to the session and transcript answers"
assert_eq "$(read_status "$H" abc-1 "" "$NOW")" "0|ok" "a reader holding no transcript matches on the session alone"
assert_eq "$(read_status "$H" nope "" "$NOW")" "1|missing" "no record for the session is missing"
assert_eq "$(read_status "$H" abc-1 /t/session-state/other/events.jsonl "$NOW")" "1|wrong-transcript" \
  "a record naming another transcript than the reader's is refused"
assert_eq "$(read_status "$H" abc-1 "" "$((NOW + COPILOT_SESSION_MAX_AGE_S + 1))")" "1|stale" \
  "a record older than the age bound is stale"
assert_eq "$(read_status "$H" abc-1 "" "$((NOW + COPILOT_SESSION_MAX_AGE_S))")" "0|ok" \
  "a record exactly at the age bound still answers"
assert_eq "$(read_status "$H" abc-1 "" "$((NOW - 5))")" "1|stale" \
  "a record stamped after the reader's clock is stale, never fresh"
cp "$RECORD" "$H/lane-status/xyz-9.json"
assert_eq "$(read_status "$H" xyz-9 "" "$NOW")" "1|wrong-session" \
  "a record whose own session id is another session's is refused whatever file it sits in"
printf 'garbage' > "$H/lane-status/bad-1.json"
assert_eq "$(read_status "$H" bad-1 "" "$NOW")" "1|unreadable" "a file that is no record is unreadable"
printf '{"session_id":"nostamp"}' > "$H/lane-status/nostamp.json"
assert_eq "$(read_status "$H" nostamp "" "$NOW")" "1|stale" "a record with no written_at is stale"

context_status() { # HOME SESSION [TRANSCRIPT]
  local rc=0 out
  out="$(copilot_session_context "$@")" || rc=$?
  copilot_session_context "$@" >/dev/null 2>&1 || true
  printf '%s|%s|%s' "$rc" "${out:--}" "${COPILOT_SESSION_REASON:-ok}"
}
assert_eq "$(context_status "$H" abc-1 /t/session-state/abc-1/events.jsonl)" "0|416000|ok" \
  "the context seam answers the record's token count"
assert_eq "$(context_status "$H" s2)" "1|-|no-figure" "a record carrying no token count answers no figure, never zero"
assert_eq "$(context_status "$H" nope)" "1|-|missing" "the seam carries the reader's reason through"

copilot_session_read "$H" abc-1 "" "$NOW"
copilot_session_fields "$COPILOT_SESSION_RECORD"
assert_eq "$CS_MODEL|$CS_USED_PCT|$CS_TOKENS|$CS_WINDOW|$CS_NANO_AIU|$CS_ALLOW_ALL" \
  "claude-fable-5.1|42|416000|1000000|258110000000|true" "the fields split as the CLI sent them, the percentage rounded"
copilot_session_fields '{"status":{"model":{"id":7},"context_window":{"used_percentage":"41","current_context_tokens":1.9}}}'
assert_eq "$CS_MODEL|$CS_USED_PCT|$CS_TOKENS|$CS_WINDOW|$CS_ALLOW_ALL" "||1||" \
  "a field of the wrong type is empty, never coerced; a fractional count is floored"

cause_status() { # RECORD
  local rc=0 out
  out="$(copilot_session_stop_cause "$1")" || rc=$?
  printf '%s|%s' "$rc" "${out:--}"
}
assert_eq "$(cause_status "$COPILOT_SESSION_RECORD")" "1|-" "a session with allow-all on names no stop cause"
run_statusline "$(session_json abc-1 /t/session-state/abc-1/events.jsonl 416000 false)" "$H"
NOW="$(stamp_of "$RECORD")"
copilot_session_read "$H" abc-1 "" "$NOW"
assert_eq "$(cause_status "$COPILOT_SESSION_RECORD")" "0|allow-all-blocked-by-policy" \
  "a session reporting allow_all_enabled false is a stop with its own cause"
assert_eq "$(cause_status '{"status":{}}')" "1|-" "a record that does not say names no cause"

# The pane binding: a record whose pid is the pane's shell or a descendant of
# it is the pane's; one under another process is not. The writer records its
# parent, so it is run from this shell directly, never inside a substitution
# whose subshell is gone before the walk reads it: the recorded pid is this
# suite's own, as a live session's is the CLI's.
COPILOT_HOME="$H" "$STATUSLINE" <<<"$(session_json pane-1 /t/session-state/pane-1/events.jsonl 1000)" >/dev/null
NOW="$(stamp_of "$H/lane-status/pane-1.json")"
pane_status() { # HOME PANE_PID [NOW]
  local rc=0
  copilot_session_for_pane "$@" || rc=$?
  printf '%s|%s|%s' "$rc" "${COPILOT_SESSION_REASON:-ok}" "$(jq -r '.session_id // "-"' <<<"${COPILOT_SESSION_RECORD:-null}")"
}
assert_eq "$(pane_status "$H" "$$" "$NOW")" "0|ok|pane-1" "a record written under the pane's shell is the pane's"
assert_eq "$(pane_status "$H" "$DEAD_PID" "$NOW")" "1|missing|-" "a pane no record was written under has none"
assert_eq "$(pane_status "$H" "$$" "$((NOW + COPILOT_SESSION_MAX_AGE_S + 1))")" "1|stale|-" \
  "a stale record under the pane is reported stale, never served"
assert_eq "$(pane_status "$TMP_ROOT/nohome" "$$" "$NOW")" "1|missing|-" "an account with no records has none"

# --- must-fail controls -----------------------------------------------------
# One per rule, each on a private copy: the library's readers and the writer.
MUT="$(mutant_scripts session-mutant lib/copilot-session.sh)" || exit 1
# The mutation and the run are two steps: mutate_file asserts at the suite's
# top level, and the run alone is captured.
mutant_lib() { # OLD NEW
  cp -- "$SCRIPTS_DIR/lib/copilot-session.sh" "$MUT/lib/copilot-session.sh"
  mutate_file "$MUT/lib/copilot-session.sh" "$1" "$2"
}
with_mutant() { # COMMAND — run with $1 the mutant library, $2 the home, $3 the clock
  bash -c "$1" _ "$MUT/lib/copilot-session.sh" "$H" "$NOW"
}
mutant_lib '{ [ "$age" -ge 0 ] && [ "$age" -le "$COPILOT_SESSION_MAX_AGE_S" ]; }' 'true'
assert_eq "$(with_mutant 'source "$1"; copilot_session_read "$2" abc-1 "" $(($3 + 100000)) && echo served || echo refused')" "served" \
  "control: without the age bound a stale record is served as fresh"
mutant_lib '[ "$rec_session" = "$session" ]' 'true'
assert_eq "$(with_mutant 'source "$1"; copilot_session_read "$2" xyz-9 "" "$3" && echo served || echo refused')" "served" \
  "control: without the session comparison another session's record answers"
mutant_lib '[ "$rec_transcript" != "$transcript" ]' 'false'
assert_eq "$(with_mutant 'source "$1"; copilot_session_read "$2" abc-1 /t/other "$3" && echo served || echo refused')" "served" \
  "control: without the transcript comparison a record naming another transcript answers"
mutant_lib '[ -n "$CS_TOKENS" ] || { COPILOT_SESSION_REASON=no-figure; return 1; }' 'CS_TOKENS="${CS_TOKENS:-0}"'
assert_eq "$(with_mutant 'source "$1"; copilot_session_context "$2" s2')" "0" \
  "control: without the no-figure refusal a record carrying no count reads as zero"
mutant_lib '[ "$CS_ALLOW_ALL" = false ] || return 1' ':'
assert_eq "$(with_mutant 'source "$1"; copilot_session_read "$2" pane-1 "" "$3"; copilot_session_stop_cause "$COPILOT_SESSION_RECORD"')" "allow-all-blocked-by-policy" \
  "control: without the flag test every session names the policy stop cause"
mutant_lib 'if [ "$pid" = "$pane" ]; then' 'if true; then'
assert_eq "$(with_mutant 'source "$1"; copilot_session_for_pane "$2" '"$DEAD_PID"' "$3" && echo bound || echo unbound')" "bound" \
  "control: without the pid walk a record under any process is the pane's"
mutant_lib "'' | . | .. | *[!A-Za-z0-9._-]*) return 1 ;;" "'') return 1 ;;"
MUTANT_HOME="$TMP_ROOT/mutant-home"
mkdir -p "$MUTANT_HOME"
run_statusline '{"session_id":"../escape"}' "$MUTANT_HOME" "$MUT/copilot-statusline"
assert_eq "$RC|$([ -e "$MUTANT_HOME/escape.json" ] && echo written || echo absent)" "0|written" \
  "control: without the alphabet rule a session id names a path outside the directory"

printf 'pass: %d   fail: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
