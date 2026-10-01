control_expect "issues bulk-get --stdin keeps the last identifier"
control_expect "issues bulk-update --stdin keeps the last identifier"
control_replace scripts/commands/issues.sh 2 \
    '        while IFS= read -r line || [ -n "$line" ]; do' \
    '        while IFS= read -r line; do'

