#!/usr/bin/env bash
# Explicit thread reads use the paged Slack reader, never channel history.
set -uo pipefail
. "$(dirname "$0")/lib/harness.sh"

sk_fake_start --page 2
echo "=== slack thread ==="
ROOT="$(sk_new_root reader)"
sk_bind "$ROOT"
CH="$(sk_channel "$ROOT")"
TOP="$(sk_inject "$CH" U001 'First &amp; foremost.')"
SECOND="$(sk_inject "$CH" U001 'Second <https://example.test|link>.' "$TOP")"
sk_inject "$CH" U002 'Third.' "$TOP" >/dev/null
sk_inject "$CH" U002 'Other topic.' >/dev/null
sk_ctl /_test/calls-reset >/dev/null
EXPECTED='First & foremost.
Second link (https://example.test).
Third.'
for ts in "$TOP" "$SECOND"; do
  sk_run -- thread "$ts" --root "$ROOT"
  assert_eq "$RC=$OUT" "0=$EXPECTED" "thread $ts prints every page oldest first as plain text"
done
assert_eq "$(sk_state '[.calls[] | select(. == "conversations.history")] | length')" "0" "explicit thread reads use no channel history"
sk_run -- thread "$TOP" --root "$ROOT" --limit 2
assert_eq "$RC=$OUT" '0=First & foremost.
Second link (https://example.test).' "--limit caps printed messages"
for limit in 0 -1 wrong; do
  sk_run -- thread "$TOP" --root "$ROOT" --limit "$limit"
  assert_eq "$RC=${ERR1%%=*}" '2=slack: usage' "--limit $limit is refused"
done
sk_ctl /_test/fault '{"method":"conversations.replies","error":"channel_not_found"}' >/dev/null
sk_run -- thread "$TOP" --root "$ROOT"
assert_eq "$RC=$ERR1" '2=slack: slack-api-failed=conversations.replies error=channel_not_found' "a refused thread read fails with Slack's cause"

sk_mutant order verbs.py 'sorted\(selected, key=lambda m: float\(m\["ts"\]\)\)' 'sorted(selected, key=lambda m: float(m["ts"]), reverse=True)'
sk_run -- thread "$TOP" --root "$ROOT"
assert_lacks "$OUT" "$EXPECTED" "control: reversing message order breaks the thread output assertion"
sk_bin_reset
sk_mutant limit verbs.py 'selected = itertools.islice\(messages, limit\) if limit is not None else messages' 'selected = messages'
sk_run -- thread "$TOP" --root "$ROOT" --limit 2
assert_has "$OUT" 'Third.' "control: dropping the limit breaks capped output"
sk_bin_reset

sk_mutant positive-limit main.py 'if args.limit is not None and args.limit < 1:' 'if args.limit is not None and False:'
sk_run -- thread "$TOP" --root "$ROOT" --limit 0
assert_eq "$RC" "0" "control: dropping positive-limit guard accepts an empty read"
sk_bin_reset

sk_summary
