# shellcheck shell=bash
# Native request journal. Callers consume the JSONL rows and usage JSON;
# linear-budget is a warning protocol, not a request refusal.

linear_usage_init() {
    source "$_LIB_DIR/cache.sh" || return 1
    LINEAR_HOURLY_BUDGET="${LINEAR_HOURLY_BUDGET:-}"
    if [[ -n "$LINEAR_HOURLY_BUDGET" ]] && ! [[ "$LINEAR_HOURLY_BUDGET" =~ ^[1-9][0-9]{0,8}$ ]]; then
        printf 'linear-budget: invalid=%s setting=LINEAR_HOURLY_BUDGET\n' "$LINEAR_HOURLY_BUDGET" >&2
        return 1
    fi
    mkdir -p -- "$CACHE_DIR" || return 1
    LINEAR_USAGE_JOURNAL="$CACHE_DIR/requests.jsonl"
}

# The worktree identifies a lane even when .cache points at the main checkout.
linear_usage_lane() {
    local name="${PROJECT_ROOT##*/}"
    if [[ "${name^^}" =~ ([A-Z][A-Z0-9]*-[0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '\n'
    fi
}

# Keep raw reset milliseconds: converting loses the server's precision.
linear_usage_headers() {
    jq -Rn '
      reduce inputs as $line ({};
        ($line | sub("\r$"; "") | capture("^(?<key>[^:]+):[ \\t]*(?<value>.*)$")? // null) as $h
        | if $h != null then .[$h.key | ascii_downcase] = $h.value else . end)
      | def number($key): .[$key] // null | if . == null then null else tonumber end;
      {remaining: number("x-ratelimit-requests-remaining"),
       limit: number("x-ratelimit-requests-limit"),
       reset: number("x-ratelimit-requests-reset"),
       endpoint_reset: number("x-ratelimit-endpoint-requests-reset"),
       complexity_reset: number("x-ratelimit-complexity-reset")}' "$1"
}

# True trailing hour, not a reset bucket. Equal shares use caller identities,
# while the command rows expose which action spent each identity's share.
linear_usage_rollup() {
    local now="$1"
    jq -s --argjson now "$now" --arg budget "$LINEAR_HOURLY_BUDGET" '
      (map(select(.epoch <= $now)) | min_by(.epoch).epoch // $now) as $first
      | map(select(.epoch > ($now - 3600) and .epoch <= $now)) as $rows
      | ($rows | map(.caller) | unique | length) as $callers
      | (if $budget != "" then ($budget | tonumber) else ($rows | map(.limit | select(. != null)) | last // null) end) as $budget
      | (if $budget == null or $callers == 0 then null else ($budget / $callers | floor) end) as $share
      | ($rows | group_by(.caller) | map({caller: .[0].caller, lane_item: .[0].lane_item,
          requests: length, share: $share, over_share: ($share != null and length > $share)})) as $identities
      | {window_start: ($now - 3600 | todateiso8601), window_end: ($now | todateiso8601),
         observed_seconds: ([3600, ($now - $first)] | min), requests: ($rows | length),
         budget: $budget, share: $share, callers: $identities,
         top_callers: ($rows | group_by([.caller, .resource, .action])
           | map({caller: .[0].caller, lane_item: .[0].lane_item, resource: .[0].resource,
                  action: .[0].action, requests: length}) | sort_by(-.requests, .caller, .resource, .action)),
         over_share: ($identities | map(select(.over_share))),
         remaining: ($rows | last | .remaining // null), reset: ($rows | last | .reset // null)}' \
      "$LINEAR_USAGE_JOURNAL"
}

linear_usage_record() (
    local headers="$1" http_code="$2" now stamp lane caller row rollup used share remaining stats reset
    now="$(date -u +%s)" || return 1
    stamp="$(date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ)" || return 1
    lane="$(linear_usage_lane)" || return 1
    caller="${LINEAR_USAGE_CALLER:-${lane:-checkout}}"
    row="$(jq -cn --argjson headers "$headers" --argjson epoch "$now" --arg utc "$stamp" \
      --arg caller "$caller" --arg lane "$lane" --arg resource "$LINEAR_USAGE_RESOURCE" \
      --arg action "$LINEAR_USAGE_ACTION" --arg code "$http_code" \
      '$headers + {utc: $utc, epoch: $epoch, caller: $caller, lane_item: $lane,
        resource: $resource, action: $action, http_status: $code}')" || return 1
    exec 198>"$CACHE_DIR/.requests.lock" || return 1
    flock 198 || return 1
    printf '%s\n' "$row" >>"$LINEAR_USAGE_JOURNAL" || return 1
    rollup="$(linear_usage_rollup "$now")" || return 1
    stats="$(jq -r --arg caller "$caller" '
      [.callers[] | select(.caller == $caller) | .requests, (.share // "unknown")]
      + [(.remaining // "unknown")] | join(" ")' <<<"$rollup")" || return 1
    read -r used share remaining <<<"$stats" || return 1
    reset="$(jq -r '.reset // "unknown"' <<<"$headers")" || return 1
    if [[ "$share" != unknown && "$remaining" != unknown ]]; then
        if (( used > share )); then
            printf 'linear-budget: caller=%s used=%s share=%s remaining=%s reset=%s\n' \
              "$caller" "$used" "$share" "$remaining" "$reset" >&2
        elif (( remaining < share )); then
            printf 'linear-budget: caller=%s remaining=%s share=%s cause=shared-quota-low reset=%s\n' \
              "$caller" "$remaining" "$share" "$reset" >&2
        fi
    fi
)

linear_usage_report() (
    local now
    linear_usage_init || return 1
    exec 198>"$CACHE_DIR/.requests.lock" || return 1
    flock 198 || return 1
    [[ -e "$LINEAR_USAGE_JOURNAL" ]] || : >"$LINEAR_USAGE_JOURNAL"
    now="$(date -u +%s)" || return 1
    linear_usage_rollup "$now"
)
