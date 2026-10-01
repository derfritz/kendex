# D017: Slack keeps bounded parent context and routes live replies at any age

[← Decision Index](INDEX.md)

**Date**: 2026-10-01

**Status**: Active

**Research**: —

**Refines**: [D009](D009-slack-relay.md) and [D014](D014-slack-socket-mode.md): only identifiers-only journal storage and age-limited live replies. Their other choices and D009's transport/topology replacements remain active.

**Decision**: The [journal schema](../../skills/slack/schemas/journal.md) owns parent fields and retention. Live owner replies route under any parent at any age. Reconnect reads and pruning remain bounded; `Binding.bound_at` owns the retained channel/journal lifetime, not delivery progress.

**Rationale**: Identifiers alone lose conversation context. A live age limit drops an owner's reply in an ongoing conversation.

**Revisit When**: Slack changes event delivery or journal retention needs change.

**Verification**: `skills/slack/tests/socket.test.sh` proves live any-age delivery; `thread-directives.test.sh` proves cached parent context and relay-root provenance; `listen.test.sh` proves stable binding lifetime and bounded reconnect reads.

**References**: KEN-2206.
