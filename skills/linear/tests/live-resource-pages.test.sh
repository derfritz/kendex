#!/bin/bash
# Recorded resource inventories through linear.sh. Cursor controls live in
# controls/live-resource-pages.control.sh; fixtures keep API keys and types.
set -euo pipefail
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/assert.sh"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
while IFS='|' read -r resource root fixture options; do
    recorded_pages_case "$resource" "$root" "$fixture" "$options"
done <<'ROWS'
issues|issues|issues|max
comments|issue.comments|comments|issue
projects|projects|projects|max
cycles|cycles|cycles|max
labels|issueLabels|labels|max
teams|teams|teams|max
users|users|users|max
statuses|workflowStates|statuses|all
milestones|projectMilestones|milestones|all
documents|documents|documents|max
project-labels|projectLabels|project-labels|max
ROWS
