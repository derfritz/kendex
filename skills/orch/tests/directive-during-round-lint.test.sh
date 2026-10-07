#!/usr/bin/env bash
# A directive during a round, ../references/skill-rules.md § Round Closure: a
# scope change reaching a running dev or fix round is read for in the dev
# agent's transcript, and one still unconfirmed takes round-recover's
# redelegate row.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/md.sh"

DIRECTIVE='#### Directive During A Round'
RULES="$SKILL_DIR/references/skill-rules.md"

echo "=== orch directive-during-round lint ==="

rule "an unconfirmed directive re-delegates through round-recover" "$RULES" "$DIRECTIVE" \
  '`redelegate`' '`round-recover`' 'agent-transcripts.md'

md_report
