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
REAL_JQ="$(command -v jq)"
cat >"$ROOT/bin/jq" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  case "$arg" in
    */requests.jsonl|*/requests-active.json)
      bytes="$(wc -c <"$arg")" || exit 1
      printf '%s %s\n' "${arg##*/}" "$bytes" >>"$TEST_JQ_READS" ;;
  esac
done
exec "$REAL_JQ" "$@"
SH
cat >"$ROOT/bin/date" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == '-u +%s' ]]; then printf '%s\n' "$TEST_NOW"; else exec "$REAL_DATE" "$@"; fi
SH
cat >"$ROOT/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >>"$TEST_CURL_LOG"
cat >/dev/null
headers="" fmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in -D) headers="$2"; shift 2;; -w) fmt="$2"; shift 2;; *) shift;; esac
done
printf 'HTTP/2 %s\r\nX-RateLimit-Requests-Limit: 12\r\nx-ratelimit-requests-remaining: %s\r\nX-RateLimit-Requests-Reset: 1790764800000\r\nX-RateLimit-Endpoint-Requests-Reset: 1790764900000\r\nX-RateLimit-Complexity-Reset: 1790765000000\r\n\r\n' "$TEST_STATUS" "$TEST_REMAINING" >"$headers"
if [[ "$TEST_STATUS" == 200 ]]; then
  printf '{"data":{"viewer":{"id":"user-id","name":"fixture"}}}'
else
  printf '{"errors":[{"message":"quota","extensions":{"code":"RATELIMITED"}}]}'
fi
printf '%s' "${fmt/\%\{http_code\}/$TEST_STATUS}"
SH
chmod +x "$ROOT/bin/date" "$ROOT/bin/curl" "$ROOT/bin/jq"
run() {
  local now="$1" status="$2" remaining="$3" budget="$4"; shift 4
  local cache_args=()
  [[ "${TEST_CACHE_ROOT:-default}" == none ]] || cache_args=("LINEAR_CACHE_ROOT=${TEST_CACHE_ROOT:-$ROOT}")
  (cd -- "${TEST_ROOT:-$ROOT}" && env -i PATH="$ROOT/bin:$PATH" HOME="$TMP_ROOT" \
    REAL_DATE="$REAL_DATE" REAL_JQ="$REAL_JQ" TEST_JQ_READS="$ROOT/jq-reads" \
    TEST_NOW="$now" TEST_STATUS="$status" TEST_REMAINING="$remaining" \
    LINEAR_API_KEY_OVERRIDE=fixture LINEAR_TEAM=fixture TEST_CURL_LOG="$ROOT/curl-log" \
    "${cache_args[@]}" \
    LINEAR_RETRY_BASE_DELAY=0 LINEAR_HOURLY_BUDGET="$budget" LINEAR_USAGE_CALLER="${TEST_CALLER:-}" \
    "$ROOT/.agents/skills/linear/scripts/linear.sh" "$@" 2>&1)
}
JOURNAL="$ROOT/.cache/linear/requests.jsonl"
ACTIVE="$ROOT/.cache/linear/requests-active.json"
run_output out rc run 10000 200 11 '' users me
assert_eq 'request succeeds' "$rc" 0
rows="$(jq -s . "$JOURNAL")"
assert_jq 'journal records request attribution and response headers' "$rows" \
  'length == 1 and .[0] == {utc:"1970-01-01T02:46:40Z",epoch:10000,caller:"KEN-2267",lane_item:"KEN-2267",resource:"users",action:"me",http_status:"200",remaining:11,limit:12,reset:1790764800000,endpoint_reset:1790764900000,complexity_reset:1790765000000}'
assert_jq 'journal records raw endpoint reset' "$rows" '.[0].endpoint_reset == 1790764900000'
assert_jq 'journal records raw complexity reset' "$rows" '.[0].complexity_reset == 1790765000000'
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
rm -f -- "$ACTIVE"
run_output out rc run 13600 200 11 1 users me
assert_not_contains 'share boundary does not warn' "$out" 'linear-budget:'
run_output out rc run 13601 200 10 1 users me
assert_contains 'over-share request emits keyed warning with remaining' "$out" 'linear-budget: caller=KEN-2267 used=2 share=1 remaining=10 reset=1790764800000'
active="$(cat "$ACTIVE")"
assert_jq 'request stores the rollup over-share result' "$active" \
  '.caller_usage == {caller:"KEN-2267",lane_item:"KEN-2267",requests:2,share:1,over_share:true}'
run_output out rc run 13601 200 10 1 usage
assert_jq 'report uses the same over-share decision' "$out" \
  '.over_share == [{caller:"KEN-2267",lane_item:"KEN-2267",requests:2,share:1,over_share:true}]'
run_output out rc run 13601 200 10 '' usage
assert_jq 'young journal reports its observed duration' "$out" '.observed_seconds == 1 and .requests == 2'
: >"$JOURNAL"
rm -f -- "$ACTIVE"
run_output out rc run 13601 200 0 12 users me
assert_contains 'low shared Remaining warns before local share is spent' "$out" 'cause=shared-quota-low'
run_output out rc run 13601 429 0 12 users me
assert_ne 'rate limit fails the command' "$rc" 0
assert_jq '429 reports the server reset' "${out##*$'\n'}" '.reset == 1790764800000'
assert_jq '429 reports endpoint and complexity resets' "${out##*$'\n'}" '.endpoint_reset == 1790764900000 and .complexity_reset == 1790765000000'
assert_eq 'each 429 retry is journaled' "$(jq -s length "$JOURNAL")" 4
run_output out rc run 13601 400 0 12 users me
assert_ne 'RATELIMITED HTTP 400 fails the command' "$rc" 0
assert_jq 'RATELIMITED HTTP 400 reports the reset' "${out##*$'\n'}" '.reset == 1790764800000'
assert_jq 'RATELIMITED HTTP 400 reports endpoint and complexity resets' "${out##*$'\n'}" '.endpoint_reset == 1790764900000 and .complexity_reset == 1790765000000'

# API answers maintain the same trailing-hour boundary as the report. A
# departed identity must not reduce the current callers share.
: >"$JOURNAL"
rm -f -- "$ACTIVE"
run_output out rc run 20000 200 11 2 users me
TEST_CALLER=overseer
run_output out rc run 20001 200 11 2 users me
TEST_CALLER=''
run_output out rc run 23600 200 11 2 users me
assert_eq 'request at the hour boundary succeeds' "$rc" 0
active="$(cat "$ACTIVE")"
assert_jq 'request snapshot keeps only active rows without report rankings' "$active" \
  '.first_epoch == 20000 and [.rows[].epoch] == [20001,23600] and .caller_usage.requests == 1 and .caller_usage.share == 1 and (has("top_callers") | not)'
run_output out rc run 23601 200 11 2 users me
active="$(cat "$ACTIVE")"
assert_jq 'request expires inactive callers and preserves observation start' "$active" \
  '.first_epoch == 20000 and [.rows[].epoch] == [23600,23601] and .caller_usage.requests == 2 and .caller_usage.share == 2 and .caller_usage.over_share == false'
assert_not_contains 'expired caller does not cause an over-share warning' "$out" 'linear-budget:'

# Measure jq input bytes, not elapsed time. Identical active snapshots give
# identical request work even after the durable archive gains expired rows.
cp -- "$ACTIVE" "$ROOT/active-baseline.json"
: >"$ROOT/jq-reads"
run_output out rc run 23602 200 11 2 users me
assert_eq 'request before archive growth succeeds' "$rc" 0
before_reads="$(cat "$ROOT/jq-reads")"
cp -- "$ROOT/active-baseline.json" "$ACTIVE"
jq -cn 'range(0;20000) | {epoch:1,caller:"expired",lane_item:"OLD-1",resource:"sync",action:"refresh",limit:12,remaining:11,reset:1790764800000}' >>"$JOURNAL"
: >"$ROOT/jq-reads"
run_output out rc run 23602 200 11 2 users me
assert_eq 'request after archive growth succeeds' "$rc" 0
assert_eq 'expired archive history adds no request-path input work' "$(cat "$ROOT/jq-reads")" "$before_reads"
assert_not_contains 'request accounting never reads the durable journal' "$(cat "$ROOT/jq-reads")" 'requests.jsonl'
assert_eq 'archive preserves expired rows and both new requests' "$(jq -s length "$JOURNAL")" 20006
run_output out rc run 23602 200 11 2 usage
assert_jq 'report ranks active requests from the preserved archive' "$out" \
  '.observed_seconds == 3600 and .requests == 4 and .top_callers[0].requests == 4 and .over_share[0].requests == 4'
printf 'invalid-json\n' >"$ACTIVE"
run_output out rc run 23602 200 11 2 users me
assert_ne 'corrupt active snapshot refuses request accounting' "$rc" 0

for budget in junk 0 01 1000000000; do
  run_output out rc run 13601 200 10 "$budget" users me
  assert_ne "invalid budget $budget refuses" "$rc" 0
  assert_contains "invalid budget $budget names its key" "$out" 'linear-budget: invalid='
done
printf 'invalid-json\n' >"$JOURNAL"
run_output out rc run 13601 200 10 '' usage
assert_ne 'corrupt journal refuses instead of an empty rollup' "$rc" 0

# Git materializes tracked .cache/.gitkeep in a linked worktree. Worktree
# setup can also omit the link when its main-checkout source is absent.
MANAGED="$TMP_ROOT/managed"
mkdir -p "$MANAGED/main/.cache"
git -C "$MANAGED/main" init -q -b main
git -C "$MANAGED/main" config gc.auto 0
git -C "$MANAGED/main" config maintenance.auto false
printf '[env]\nWORKTREE_SYMLINKS = ".cache//"\n' >"$MANAGED/main/kendex.settings.toml"
touch "$MANAGED/main/.cache/.gitkeep"
git -C "$MANAGED/main" add .cache/.gitkeep kendex.settings.toml
git -C "$MANAGED/main" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -qm base
git -C "$MANAGED/main" worktree add -qb lane "$MANAGED/ken-2270"
TEST_ROOT="$MANAGED/ken-2270"
TEST_CACHE_ROOT=none
while read -r state main_cache; do
  rm -rf -- "$TEST_ROOT/.cache" "$MANAGED/main/.cache"
  [[ "$state" != materialized ]] || mkdir -p "$TEST_ROOT/.cache"
  [[ "$main_cache" != present ]] || mkdir -p "$MANAGED/main/.cache"
  : >"$ROOT/curl-log"
  run_output out rc run 24000 200 11 '' users me
  assert_ne "managed $state cache with $main_cache main cache refuses usage initialization" "$rc" 0
  assert_contains "managed $state cache delegates the refusal" "$out" 'Cache-refused:'
  assert_not "managed $state cache refuses before curl" test -s "$ROOT/curl-log"
  assert_not "managed $state cache creates no local journal directory" test -e "$TEST_ROOT/.cache/linear"
done <<'CASES'
materialized present
materialized missing
missing present
missing missing
CASES

mkdir -p "$MANAGED/main/.cache"
ln -s "$MANAGED/main/.cache" "$TEST_ROOT/.cache"
run_output out rc run 24000 200 11 '' users me
assert_eq 'intact worktree link permits request journaling' "$rc" 0
assert_jq 'worktree link journals in the shared main cache' "$(jq -s . "$MANAGED/main/.cache/linear/requests.jsonl")" \
  'length == 1 and .[0].lane_item == "KEN-2270"'
rm -- "$TEST_ROOT/.cache"
printf '[env]\nWORKTREE_SYMLINKS = "tmp"\n' >"$TEST_ROOT/kendex.settings.toml"
run_output out rc run 24000 200 11 '' users me
assert_eq 'explicit cache opt-out permits local request journaling' "$rc" 0
assert 'explicit cache opt-out creates its local journal' test -s "$TEST_ROOT/.cache/linear/requests.jsonl"

printf '[env]\nWORKTREE_SYMLINKS = ".cache"\n' >"$TEST_ROOT/kendex.settings.toml"
TEST_CACHE_ROOT="$MANAGED/main"
run_output out rc run 24001 200 11 '' users me
assert_eq 'cache redirect bypasses the broken caller worktree link' "$rc" 0
assert_jq 'cache redirect journals in the selected main cache' "$(jq -s . "$MANAGED/main/.cache/linear/requests.jsonl")" \
  'length == 2 and .[1].lane_item == "KEN-2270"'
