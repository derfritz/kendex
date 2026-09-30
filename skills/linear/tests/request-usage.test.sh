#!/usr/bin/env bash
# Journal, trailing-hour counts, warning protocol, and reset-bearing refusals.
set -euo pipefail
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
assert_tmpdir TMP_ROOT
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)"
ROOT="$TMP_ROOT/ken-2267"
mkdir -p "$ROOT/bin" "$ROOT/.agents/skills"
cp -R "$SKILL_DIR" "$ROOT/.agents/skills/linear"
git -C "$ROOT" init -q
git -C "$ROOT" config gc.auto 0
git -C "$ROOT" config maintenance.auto false
export LINEAR_CACHE_ROOT="$ROOT"
REAL_DATE="$(command -v date)"
cat >"$ROOT/bin/date" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == '-u +%s' ]]; then printf '%s\n' "$TEST_NOW"; else exec "$REAL_DATE" "$@"; fi
SH
cat >"$ROOT/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
headers="" fmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in -D) headers="$2"; shift 2;; -w) fmt="$2"; shift 2;; *) shift;; esac
done
printf 'HTTP/2 %s\r\nX-RateLimit-Requests-Limit: 12\r\nx-ratelimit-requests-remaining: %s\r\nX-RateLimit-Requests-Reset: 1790764800000\r\n\r\n' "$TEST_STATUS" "$TEST_REMAINING" >"$headers"
if [[ "$TEST_STATUS" == 200 ]]; then
  printf '{"data":{"viewer":{"id":"user-id","name":"fixture"}}}'
else
  printf '{"errors":[{"message":"quota","extensions":{"code":"RATELIMITED"}}]}'
fi
printf '%s' "${fmt/\%\{http_code\}/$TEST_STATUS}"
SH
chmod +x "$ROOT/bin/date" "$ROOT/bin/curl"
run() {
  local now="$1" status="$2" remaining="$3" budget="$4"; shift 4
  (cd -- "$ROOT" && env -i PATH="$ROOT/bin:$PATH" HOME="$TMP_ROOT" \
    REAL_DATE="$REAL_DATE" TEST_NOW="$now" TEST_STATUS="$status" TEST_REMAINING="$remaining" \
    LINEAR_API_KEY_OVERRIDE=fixture LINEAR_TEAM=fixture LINEAR_CACHE_ROOT="$ROOT" \
    LINEAR_RETRY_BASE_DELAY=0 LINEAR_HOURLY_BUDGET="$budget" \
    "$ROOT/.agents/skills/linear/scripts/linear.sh" "$@" 2>&1)
}
JOURNAL="$ROOT/.cache/linear/requests.jsonl"
run_output out rc run 10000 200 11 '' users me
assert_eq 'request succeeds' "$rc" 0
rows="$(jq -s . "$JOURNAL")"
assert_jq 'journal records request attribution and response headers' "$rows" \
  'length == 1 and .[0] == {utc:"1970-01-01T02:46:40Z",epoch:10000,caller:"KEN-2267",lane_item:"KEN-2267",resource:"users",action:"me",http_status:"200",remaining:11,limit:12,reset:1790764800000,endpoint_reset:null,complexity_reset:null}'
assert_not_contains 'journal has no authorization secret' "$rows" 'fixture'

# Independent timestamps put one row on the excluded boundary and one just
# inside it. Caller shares count identities, not command rows.
jq -cn '[
 {epoch:9999,caller:"old",lane_item:"OLD-1",resource:"sync",action:"refresh",limit:12,remaining:11,reset:1790764800000},
 {epoch:10000,caller:"boundary",lane_item:"BOUND-1",resource:"sync",action:"refresh",limit:12,remaining:10,reset:1790764800000},
 {epoch:10001,caller:"KEN-2267",lane_item:"KEN-2267",resource:"users",action:"me",limit:12,remaining:9,reset:1790764800000},
 {epoch:13599,caller:"overseer",lane_item:"",resource:"issues",action:"list",limit:12,remaining:8,reset:1790764800000},
 {epoch:13599,caller:"overseer",lane_item:"",resource:"issues",action:"list",limit:12,remaining:7,reset:1790764800000},
 {epoch:13599,caller:"overseer",lane_item:"",resource:"issues",action:"list",limit:12,remaining:6,reset:1790764800000},
 {epoch:13599,caller:"overseer",lane_item:"",resource:"issues",action:"list",limit:12,remaining:5,reset:1790764800000}][]' >"$JOURNAL"
run_output out rc run 13600 200 5 6 usage
assert_eq 'usage succeeds without a request' "$rc" 0
assert_jq 'usage counts a trailing hour and top callers' "$out" \
  '.requests == 5 and .observed_seconds == 3600 and .share == 3 and .top_callers[0] == {caller:"overseer",lane_item:"",resource:"issues",action:"list",requests:4} and .over_share == [{caller:"overseer",lane_item:"",requests:4,share:3,over_share:true}]'
assert_eq 'usage leaves the journal unchanged' "$(jq -s length "$JOURNAL")" 7
run_output out rc run 13600 200 5 '' usage
assert_jq 'budget defaults to the header limit' "$out" '.budget == 12 and .share == 6'

# Cross a share, not merely touch it. Warnings inspect the returned balance.
: >"$JOURNAL"
run_output out rc run 13600 200 11 1 users me
assert_not_contains 'share boundary does not warn' "$out" 'linear-budget:'
run_output out rc run 13601 200 10 1 users me
assert_contains 'over-share request emits keyed warning with remaining' "$out" 'linear-budget: caller=KEN-2267 used=2 share=1 remaining=10 reset=1790764800000'
run_output out rc run 13601 200 10 '' usage
assert_jq 'young journal reports its observed duration' "$out" '.observed_seconds == 1 and .requests == 2'
: >"$JOURNAL"
run_output out rc run 13601 200 0 12 users me
assert_contains 'low shared Remaining warns before local share is spent' "$out" 'cause=shared-quota-low'
run_output out rc run 13601 429 0 12 users me
assert_ne 'rate limit fails the command' "$rc" 0
assert_contains '429 reports the server reset' "$out" '"reset":1790764800000'
assert_eq 'each 429 retry is journaled' "$(jq -s length "$JOURNAL")" 4
run_output out rc run 13601 400 0 12 users me
assert_contains 'RATELIMITED HTTP 400 reports the reset' "$out" '"reset":1790764800000'

for budget in junk 0 01 1000000000; do
  run_output out rc run 13601 200 10 "$budget" users me
  assert_ne "invalid budget $budget refuses" "$rc" 0
  assert_contains "invalid budget $budget names its key" "$out" 'linear-budget: invalid='
done
printf 'invalid-json\n' >"$JOURNAL"
run_output out rc run 13601 200 10 '' usage
assert_ne 'corrupt journal refuses instead of an empty rollup' "$rc" 0
