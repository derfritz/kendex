# Drop the blocker state type while keeping the page-aware selection.
control_expect "live get safe filters by state type"
control_expect "production inverse projection requests state type"
control_replace scripts/lib/formatters.sh 1 \
    'readonly ISSUE_BLOCKED_BY_FIELDS='"'"'inverseRelations(first: 10) { pageInfo { hasNextPage endCursor } nodes { id type issue { id identifier title state { name type } } } }'"'"'' \
    'readonly ISSUE_BLOCKED_BY_FIELDS='"'"'inverseRelations(first: 10) { pageInfo { hasNextPage endCursor } nodes { id type issue { id identifier title state { name } } } }'"'"''

control_expect "live relations keep history and filter open blockers"
control_replace scripts/lib/formatters.sh 1 \
    'def issue_is_open: (.state.type | IN("completed", "canceled") | not);' \
    'def issue_is_open: true;'

control_expect "production GraphQL has one inverse relation projection owner"
control_append scripts/commands/issues.sh \
    "BYPASS_RELATION_QUERY='inverseRelations(first: 10) { pageInfo { hasNextPage endCursor } nodes { id type issue { identifier } } }'"
