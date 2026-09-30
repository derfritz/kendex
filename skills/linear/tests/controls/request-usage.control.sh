#!/usr/bin/env bash
control_expect 'journal records request attribution and response headers'
control_replace scripts/lib/common.sh 1 \
  '        linear_usage_record "$headers" "$http_code" || return 1' \
  '        linear_usage_record "$headers" "000" || return 1'

control_expect 'usage counts a trailing hour and top callers'
control_replace scripts/lib/usage.sh 1 \
  '      | map(select(.epoch > ($now - 3600) and .epoch <= $now)) as $rows' \
  '      | map(select(.epoch >= ($now - 3600) and .epoch <= $now)) as $rows'

control_expect 'over-share request emits keyed warning with remaining'
control_replace scripts/lib/usage.sh 1 \
  '        if (( used > share )); then' \
  '        if false; then'

control_expect '429 reports the server reset'
control_replace scripts/lib/common.sh 1 \
  '                '\''{error: "Rate limited. Try again later.", reset: $headers.reset,' \
  '                '\''{error: "Rate limited. Try again later.", reset: null,'

control_expect 'invalid budget junk names its key'
control_replace scripts/lib/usage.sh 1 \
  '    if [[ -n "$LINEAR_HOURLY_BUDGET" ]] && ! [[ "$LINEAR_HOURLY_BUDGET" =~ ^[1-9][0-9]{0,8}$ ]]; then' \
  '    if false; then'
