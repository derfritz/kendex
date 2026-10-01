# Stop after the first page although Linear leaves the connection open.
control_expect 'issues: cursor chain closes'
control_replace scripts/lib/pages.sh 1 \
    '        if [[ "$next" == false ]]; then break; fi' \
    '        if [[ "$next" == false || "$count" == 1 ]]; then break; fi'
