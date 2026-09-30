#!/usr/bin/env bash
control_expect 'journal records request attribution and response headers'
control_replace scripts/lib/common.sh 1 \
  '        linear_usage_record "$headers" "$http_code" || return 1' \
  '        linear_usage_record "$headers" "000" || return 1'

control_expect 'usage counts a trailing hour and top callers'
control_replace scripts/lib/usage.sh 1 \
  '      | ($state.rows | map(select(.epoch > ($now - 3600) and .epoch <= $now))) as $rows' \
  '      | ($state.rows | map(select(.epoch >= ($now - 3600) and .epoch <= $now))) as $rows'

control_expect 'over-share request emits keyed warning with remaining'
control_replace scripts/lib/usage.sh 1 \
  '        if [[ "$over_share" == true ]]; then' \
  '        if false; then'

control_expect 'report uses the same over-share decision'
control_replace scripts/lib/usage.sh 1 \
  '      | def usage: . + {share: $share, over_share: ($share != null and .requests > $share)};' \
  '      | def usage: . + {share: $share, over_share: ($share != null and .requests > $share and false)};'

control_expect 'request snapshot keeps only active rows without report rankings'
control_replace scripts/lib/usage.sh 1 \
  '      if $mode == "request" then' \
  '      if false then'

control_expect 'expired archive history adds no request-path input work'
control_expect 'request accounting never reads the durable journal'
control_replace scripts/lib/usage.sh 1 \
  '        request) input="$LINEAR_USAGE_ACTIVE" ;;' \
  '        request) input="$LINEAR_USAGE_JOURNAL" ;;'

control_expect 'low shared Remaining warns before local share is spent'
control_replace scripts/lib/usage.sh 1 \
  '        elif (( remaining < share )); then' \
  '        elif false; then'

control_expect '429 reports the server reset'
control_replace scripts/lib/common.sh 1 \
  '                '\''{error: "Rate limited. Try again later.", reset: $headers.reset,' \
  '                '\''{error: "Rate limited. Try again later.", reset: null,'

control_expect 'invalid budget junk names its key'
control_replace scripts/lib/usage.sh 1 \
  '    if [[ -n "$LINEAR_HOURLY_BUDGET" ]] && ! [[ "$LINEAR_HOURLY_BUDGET" =~ ^[1-9][0-9]{0,8}$ ]]; then' \
  '    if false; then'

control_expect 'journal records raw endpoint reset'
control_replace scripts/lib/usage.sh 1 \
  '       endpoint_reset: number("x-ratelimit-endpoint-requests-reset"),' \
  '       endpoint_reset: (number("x-ratelimit-endpoint-requests-reset") | null),'

control_expect 'journal records raw complexity reset'
control_replace scripts/lib/usage.sh 1 \
  '       complexity_reset: number("x-ratelimit-complexity-reset")}'\'' "$1"' \
  '       complexity_reset: (number("x-ratelimit-complexity-reset") | null)}'\'' "$1"'
