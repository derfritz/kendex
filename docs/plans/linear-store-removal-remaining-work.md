# Linear store removal: remaining work

KEN-2335 remains blocked by the page reader's argument-size failure and missing contract proof.

## Framing

- **Goal**: finish the committed store removal without changing retained command names, arguments or output shapes.
- **Perspective**: divide the remaining technical work at existing code and proof owners. Each piece has its own closure evidence. A piece's closure does not close KEN-2335.
- **Constraints read**: `tmp/planner-brief-KEN-2335.md`, the owner contract in `tmp/dev-brief-KEN-2335.md`, the final owner ruling, the mandatory failure and contract receipts below, repository instructions, code-quality and docs-writing. Apply code-quality's Over-Engineering rule.
- **Assumptions**: any execution needs a new owner-approved delegation. This plan grants no permission to edit code, run checks, record API calls or change tracker records.
- **Preserved state**: branch `ken-2335`, HEAD `d19e00429c1d1fde61947543ee6840877436ef68`, migration commit `12e3f275460605d1964062a5670b04c3c3ae3f43`. Preserve the dirty source/render attachment pair. No PR or push exists.
- **Lane boundary**: all later authorized work stays in this worktree. Never use `sync --reconcile`, `kendex refresh` or `kendex apply`. Never write the sandbox base checkout, its lock or `.kendex-lock.json`. Replay source diffs into tracked renders. Never copy a source over a render or amend a reported commit.
- **Current proof**: no configured validation ran in the stopped round. The strict-auth step after the failed session capture was not reached. No scratch issue exists. No cancellation is currently owed.

## Evidence basis

| Evidence | What it establishes |
|---|---|
| `tmp/owner-final-failure-KEN-2335.md` | The owner holds the branch and requests this plan only. |
| `tmp/dev-return-KEN-2335-1790888486278109847-4411.json` | Valid failing return: `FAILING: session-status recorded contract`. |
| `tmp/waiter.xVikeR/reads.exit`, `reads.log`, `reads.runner` | Recording exited nonzero. No later repair, promotion or validation followed. |
| `tmp/open-contracts-KEN-2335-1790888486278109847-4411.md` | Exact retained contracts and checks still open. |
| `tmp/PR-body-KEN-2335-1790888486278109847-4411.md` | Exact non-issue recording cut and PR handoff obligations. |
| `tmp/removed-callers-KEN-2335.md` | Existing caller replacements, including source/render forms. Its external-gate wording is superseded by the cleared consumer gate below. |
| `tmp/record-contracts/`, `tmp/recorded-api/` | Private captures. A saved capture is not a shipped replay or a passing suite. |
| `skills/linear/tests/fixtures/recorded/README.md` | Shipped inventory replay provenance. It does not establish the still-missing per-command contracts. |

The failed `session-status` request returned HTTP 200. Its body was 345761 bytes. `skills/linear/scripts/lib/pages.sh:25` passed the node array through `jq --argjson nodes`. The operating system refused the argument before jq ran. This failure prevents session initialization from returning its complete status. It happened on the real workspace response. Its frequency beyond that response is unknown.

The dirty attachment correction uses `issue.attachments` with `$id: String!`. The final attachment capture succeeded. Its connection had one node and `hasNextPage: false`. It proves neither continuation nor refusal of an incomplete chain.

## Approach

- Keep `skills/linear/scripts/linear.sh` as the API entry point.
- Keep `graphql_request` in `scripts/lib/common.sh` as the GraphQL transport.
- Repair the full response-size defect class in `scripts/lib/pages.sh`. Keep traversal and nested completion there.
- Send response-sized JSON to jq through standard input. Use jq's existing slurp and structural update operations. Keep arguments for bounded control values, not node arrays, entities or accumulated replies.
- Extend `tests/live-resource-pages.test.sh`, `tests/lib/assert.sh::recorded_pages_case`, existing command suites and `tests/controls/`. Keep `tests/must-fail-controls.sh` as the Linear control runner.
- Keep `tools/guard`, `tools/ci-job-set` and orch's `dev-validate-run` as the check-selection and validation owners. Use orch's existing `scripts/lib/job-unit.sh` for authorized recordings and standalone suite jobs.
- Reject a smaller page size as a fix. Accumulated rows and a single large entity can still exceed an argument limit.
- Reject a new client, service, MCP route, forwarding wrapper, selector, dependency table or runner. These concerns already have owners.
- Accept in-memory assembly for this change. It preserves the no-partial-output contract without adding a persistent store. This plan makes no memory or speed claim.

## Proof rules for every piece

- A **capture** records a successful complete command and its actual request/reply sequence.
- A **shipped replay** is a redacted fixture exercised through the real `linear.sh` entry point in an isolated test checkout.
- A **passing suite** has an exit receipt and named assertions for that fixture and contract.
- A **passing control** shows that a planted defect in a disposable copy reddens its own named assertion. A timeout or an unrelated failure is not proof.
- Keep captures private. Promote request/reply JSON and required provenance only. Never promote raw headers, cookies, credentials or private tracker text.
- Preserve keys, types, enums, nulls, ordering and reference relationships during redaction. Use distinct, consistent fixture identifiers. Mapping every issue to the same identifier would invalidate bulk and relation proof.
- Use recorded wire replies for `pageInfo`. Do not invent a closed connection from formatted output. Label forced cursor pages, oversized padding and error injection as derived offline controls, not live recordings.
- Extend assertion helpers only in the existing assertion library. Extend `recorded_pages_case` there so command rows can carry their arguments and complete transcripts. Do not add a second replay implementation to each suite.
- Each new contract fixture contains `args`, `wire` and independent contract expectations. Each `wire` entry contains the recorded request query/variables, reply body, HTTP status and credential class. It contains no header or credential value. The helper consumes the ordered transcript, checks requests and refuses unused or missing replies. Derived complete/partial scenarios use the same helper and remain labeled controls.
- Each closure record names its source capture, shipped fixture, command arguments, assertions, suite receipt and control receipt. Keep runtime records under this worktree's `tmp/`.
- Until a new delegation authorizes checks, all Done-when clauses below remain untested.

## Ordered pieces

Unless a row names another package, `scripts/`, `tests/` and `lib/` below are relative to `skills/linear/`. Every piece uses the shared proof rules above.

### 1. Page reader payload handling and traversal proof

**Scope and owners**

- `skills/linear/scripts/lib/pages.sh`: `graphql_pages`, `linear_complete_entity`, `linear_complete_result`, `graphql_query`.
- Its tracked render: `.agents/skills/linear/scripts/lib/pages.sh`.
- `skills/linear/tests/live-resource-pages.test.sh`, `tests/lib/assert.sh`, `tests/controls/live-resource-pages.control.sh`.
- Transport remains `scripts/lib/common.sh::graphql_request`. Resolvers in that file and resource command files remain its consumers.

**Change intent**

- Replace every response-sized argument transfer in the page owner, not only the failing append. This includes `all` and `nodes` accumulation, final `setpath`, entity wrapping, connection replacement, child accumulation, root row accumulation and create/update reply reassembly.
- Feed whole JSON values as separate standard-input documents to jq. Keep path and field metadata separate from response data. Check each parse, merge and recursive completion result before returning output.
- Review `variables`, cursor and seen-cursor handling for the same failure class. Do not move a response-sized value into an environment variable or another external command's arguments.
- Preserve bounded listing behavior and complete `--max` behavior. Preserve the existing page cap. An incomplete requested chain fails nonzero with empty stdout.
- Keep nested fields and requested child depth in the existing field owners. Complete labels, both issue relation directions, children and comments; project labels, teams, dependencies and updates; initiative projects; team members, labels and states; user/viewer teams; organization teams; milestone issues. Absent, unrequested fields stay absent.

**Dependencies**: new owner authorization only.

**Done-when**

- The sanitized failed first-page shape passes through the page owner without an argument-size error.
- Oversized single pages, cumulative pages, single entities, nested connections, child rows and mutation reply envelopes reach each reassembly path. Root and nested continuation return all requested rows.
- Missing or malformed connection metadata, a failed later page, a missing cursor, a repeated cursor and an open chain at the page cap each refuse without partial output. Bounded reads stop at their requested bound without being called complete inventories.
- A control that restores the response-sized argument transfer fails the relevant oversized assertion. Independent chain rules have their own controls. Removing the whole function is not a control.

**Closure evidence**: source/render diff; a reviewed inventory of response-data argument sites in this owner; sanitized failure-shape provenance; suite and control receipts. This is an offline repair piece. A complete live session capture belongs to piece 5.

### 2. Attachment command proof and capture promotion

**Scope and owners**

- Preserve `skills/linear/scripts/commands/attachments.sh::list_attachments` and its dirty tracked render correction.
- Extend the replay suite, assertion library and controls named in piece 1.
- Promote `tmp/record-contracts/attachments-final/` into `skills/linear/tests/fixtures/recorded/contracts/attachments.json`.

**Change intent**

- Replay the complete recorded command: issue resolution, `issue.attachments`, issue description and comments.
- Pin `String!` and the nested attachment root from the successful request. Reject the prior `AttachmentFilter.issue` and `ID!` forms in query-contract assertions.
- Prove attachment pagination plus any requested issue/comment continuation. Preserve output fields, repository references, URL deduplication and explicit-download behavior.
- Review the command's own JSON joins. Its current `links` join passes whole issue/comment replies through `--argjson`; its final join passes full record/link arrays. Convert these response-sized joins to standard input in this owner if retained by the replayed path.
- Keep `fetch_attachment` as the download owner. Preserve host refusal, explicit destination, failure behavior and temporary-file cleanup. Do not introduce a local attachment inventory.

**Dependencies**: piece 1.

**Done-when**

- The successful capture is a shipped replay, not only a private receipt.
- Forced complete attachment and comment chains return all rows. A later failure in either chain returns nonzero and no attachment array.
- Oversized description/comment/link inputs do not fail at a command-local jq argument transfer.
- Controls redden attachment continuation and partial-result assertions. A synthetic continuation is identified as a control, not a newly recorded live page.

**Closure evidence**: capture-to-fixture provenance; source/render pair; named complete, partial and oversized assertions; replay/control receipts; explicit-download regression proof from the existing suite owner or a case in the same replay suite.

### 3. Issue and bulk-comment read captures

**Scope and owners**

- `scripts/commands/issues.sh`: get, bundle, bulk-get, children, recursive children and relation readers.
- `scripts/commands/comments.sh`: bulk-list.
- `scripts/lib/formatters.sh`: relation projections and normalized issue output.
- Extend the existing replay owner. Keep blocker behavior in `tests/blocked-by-open.test.sh` and `tests/controls/blocked-by-open.control.sh`. Keep GitHub-link behavior in `tests/issues-get-github-sync.test.sh`.

| Required captured command | Private capture directory | Shipped fixture under `tests/fixtures/recorded/contracts/` |
|---|---|---|
| `issues get KEN-2335 --format=raw` | `tmp/record-contracts/issue-get/` | `issue-get.json` |
| `issues get KEN-2335 --with-bundle --format=safe` | `tmp/record-contracts/issue-bundle/` | `issue-bundle.json` |
| `issues bulk-get KEN-2335 KEN-2319 --format=safe` | `tmp/record-contracts/issue-bulk/` | `issue-bulk.json` |
| `issues children KEN-2335 --format=safe` | `tmp/record-contracts/issue-children/` | `issue-children.json` |
| `issues children KEN-2335 --recursive --format=safe` | `tmp/record-contracts/issue-descendants/` | `issue-descendants.json` |
| `issues list-relations KEN-2335 --format=safe` | `tmp/record-contracts/issue-relations/` | `issue-relations.json` |
| `comments bulk-list KEN-2335 KEN-2319 --format=raw` | `tmp/record-contracts/comments-bulk/` | `comments-bulk.json` |

**Change intent**: promote these successful captures without another live read. Preserve raw nesting, safe shapes, keyed bulk comments, recursive depth and blocker history. Retain terminal blockers in `blocked_by`; only nonterminal blockers enter `blocked_by_open`.

**Dependencies**: piece 1 and its replay extension.

**Done-when**

- Every table row has a shipped replay and a passing assertion for its own output contract.
- Root and nested chain controls cover requested relations, labels, comments and each requested descendant level. Empty captured collections do not substitute for a continuation test.
- Bulk input matching and unmatched-identifier behavior remain explicit. A failed issue or comment read never becomes an empty successful batch.
- Existing blocker and GitHub-link suites and their controls pass on the affected files.

**Closure evidence**: a table mapping every row to capture, fixture, assertions and receipts. Identify derived nested-page controls separately from captured rows. No new issue writes belong to this piece.

### 4. Planning, project and viewer read captures

**Scope and owners**

- `scripts/commands/initiatives.sh`, `projects.sh`, `users.sh`; their field and formatter owners in `lib/pages.sh` and `lib/formatters.sh`.
- Extend the same replay suite and assertion library. Keep existing inventory fixtures and `tests/projects-list-pagination.test.sh` with its control.

| Required captured command | Private capture directory | Shipped fixture under `tests/fixtures/recorded/contracts/` |
|---|---|---|
| `initiatives list --max --format=raw` | `tmp/record-contracts/initiatives/` | `initiatives.json` |
| `projects get 84dff092-534c-4f71-bcea-3f56b301ab8f --format=safe` | `tmp/record-contracts/project-get/` | `project-get.json` |
| `projects list-dependencies 84dff092-534c-4f71-bcea-3f56b301ab8f --format=safe` | `tmp/record-contracts/project-dependencies/` | `project-dependencies.json` |
| `projects list-updates 84dff092-534c-4f71-bcea-3f56b301ab8f` | `tmp/record-contracts/project-updates/` | `project-updates.json` |
| `users me --format=safe` | `tmp/record-contracts/viewer/` | `viewer.json` |

**Change intent**: promote complete transcripts and preserve project dependency direction, project updates, initiative project fields and viewer output. Update the recorded-fixture README. It currently says initiatives are not recorded. Distinguish the recording-only personal-key initiative exception from application-actor captures.

**Dependencies**: piece 1.

**Done-when**: every table row has its own replay assertions, complete requested-chain proof and must-fail partial-chain control. Existing issue, comment, project, cycle, label, team, user, status, milestone, document and project-label inventory fixtures remain exercised. No app token is minted and no auth scope changes.

**Closure evidence**: capture-to-fixture table and replay/control receipts, including existing inventory coverage. Inspect earlier `tmp/recorded-api/` provenance before reuse. A filename or nonempty body alone is not a successful contract receipt.

### 5. Session-status completion and new capture

**Scope and owners**

- `scripts/commands/session-status.sh::get_session_status` and tracked render.
- Existing issues, projects, cycles, cycle-date and relation formatter owners.
- Existing replay suite, assertion library and controls.

**Change intent**

- After piece 1, review the session command's own large JSON joins. Its project lookup, `projects_with_work` assembly and final jq assembly still use response-derived `--argjson` values. Use standard input in this command owner where those values can grow. Do not add a session service or a parallel query client.
- Keep research, active projects, backlog projects, dependency readiness, cycle selection, categorized issues, children progress and PR blockers in their current output shapes.
- Record the complete command through the existing recorder and job runner. Use a fresh private capture directory. Preserve the incomplete `tmp/record-contracts/session/` as failure evidence.
- Promote the successful new transcript to `tests/fixtures/recorded/contracts/session.json`.

**Dependencies**: pieces 1, 3 and 4. Use production application authentication. Read-only recording still needs a new delegation.

**Done-when**

- The complete command returns its status after all requested issues, projects, cycles and nested connections finish.
- The large-input path passes both the page owner and session-local assembly. No assembly failure returns a partial status.
- A failed later root or nested read leaves stdout empty. Controls prove that session initialization cannot succeed with an incomplete input inventory.
- Cycle boundaries and blocker-history semantics remain pinned by existing owners, not redefined by the replay helper.

**Closure evidence**: fresh complete capture receipt, shipped fixture provenance, output-shape assertions and suite/control receipts. HTTP 200 for the old first page cannot close this piece.

### 6. Store retirement, removed verbs and OAuth regression proof

**Scope and owners**

- `scripts/linear.sh`: removed-verb refusal.
- `scripts/lib/common.sh`: existing `LINEAR_CACHE_ROOT` retirement guard after `kendex_load_project_env`.
- `scripts/lib/auth.sh`, `commands/auth-check.sh`, `commands/auth-mint.sh`: in-memory credential lifetime.
- `tests/settings-retirement.test.sh`, `tests/oauth-auth.test.sh`, `tests/api-key-precedence.test.sh`, `tests/team-target-fail-closed.test.sh`, `tests/bash4-runtime-contract.test.sh`; their matching files under `tests/controls/`.
- Extend `tests/live-resource-pages.test.sh` for removed-verb refusal rows through the existing assertion library. The router remains their production owner.
- `skills/linear/kendex.settings.toml.example`, `skills/orch/kendex.settings.toml.example`, installed example pairs and `kendex.settings.toml`.

**Change intent**

- Audit the committed removal, rather than rebuilding it. Confirm removed sync/cache implementations, cache libraries, cache settings and store-only suites remain deleted. Keep command refusal only; do not restore compatibility implementations.
- Extend the existing refusal/assertion owners to pin each removed verb's single diagnostic line, live replacement and nonzero exit before API or filesystem work.
- Keep setting retirement in the package's existing loader/refusal path. Prove present-empty and present-valued `LINEAR_CACHE_ROOT` from process, private and public settings layers. Do not add a registry or a second loader.
- Confirm removed orch sync thresholds have no remaining reader or shipped declaration. Name their exact old keys in the closure inventory from the removed owner, not from a guessed list.
- Prove application-token precedence, incomplete-pair refusal, per-invocation pair minting, one HTTP 401 renewal and no persistent OAuth store with the existing OAuth suite. Live initiative recording remains a personal-key exception only.
- Correct `kendex.settings.toml`'s stale comment that OAuth tokens live in the Linear cache. Keep secrets and user settings unchanged.

**Dependencies**: piece 1 for tests that read through the helper. The retirement audit can proceed independently under authorization.

**Done-when**: removed commands and settings meet their refusal contracts; no retained invocation creates `.cache/linear`; existing OAuth, precedence, runtime and team-target suites and controls pass. No authentication architecture or mint scope changes.

**Closure evidence**: removal inventory over the full affected tree, retirement layer cases, command refusal assertions and suite/control receipts. Document the existing package retirement path. Do not use `refresh` to prove it.

### 7. Quota diagnostics and held-write proof

**Scope and owners**

- `scripts/lib/common.sh::graphql_request` owns error classification and `Requests-Reset`.
- `tests/rate-limited-http-400.test.sh` and its control own transport quota proof.
- `skills/linear/patterns/workflow-actions.md::Quota holds`, affected dev/orch workflow text and their renders own activation/completion hold behavior.
- `skills/orch/scripts/lib/job-unit.sh` and `skills/orch/references/waiter-launch.md` own waiting and receipts. `skills/orch/tests/job_unit.sh` owns job lifecycle proof. Do not move waiting into another API client.

**Change intent**

- Update the stale quota assertions. The suite still expects `Rate limited. Try again later.`; the transport now reports `Rate limited. Requests-Reset=...`. Pin the reset field and error classification, not the old prose.
- Add offline header cases for quota replies served as HTTP 400 with `RATELIMITED` and direct HTTP 429. Pin a valid reset and explicit unavailable-reset behavior. Keep generic HTTP errors separate.
- Prove the existing workflow path preserves an activation/completion command and body under `tmp/`, waits through the job runner until reset and retries the plain command once. A second quota error returns held work to the caller. Unknown reset cannot authorize an immediate write or a retry loop.
- Use fixture time and job records. Do not induce a live quota failure or spend a real reset wait just to test it.

**Dependencies**: piece 6. Keep transport assertions in the Linear suite. Keep job lifecycle assertions in `skills/orch/tests/job_unit.sh`, with its existing test helpers and controls. Review the agent workflow's reset calculation, preserved command/body and single retry against those proved interfaces. The workflow is instruction text, not a runtime scheduler; do not build a new scheduler to test it.

**Done-when**: reset output and error classification pass their tests and independent controls. Held activation and completion have proved wait/retry boundaries. Neither a quota refusal nor a failed wait becomes successful completion.

**Closure evidence**: transport suite/control receipts; offline hold, wait and retry records from the existing workflow/job owner; source/render documentation diff where behavior wording changes. No live record changes belong to this piece.

### 8. Scratch issue-write contracts and cancellation

**Scope and owners**

- `scripts/commands/issues.sh`, `scripts/lib/issue-validation.sh`, existing resolvers and GraphQL helper.
- Existing suites and their matching controls own the command assertions below. Extend their recorded transcript cases through `tests/lib/assert.sh`. Do not add a mutation runner.

| Command family | Existing suite owners under `skills/linear/tests/` | Fixture under `fixtures/recorded/contracts/issue-writes/` |
|---|---|---|
| `create` | `issues-create-parent.test.sh`, `issues-create-agent-label-guard.test.sh`, `issues-create-reach-guard.test.sh`, `issues-create-format-ids.test.sh` | `create.json` |
| `update` | `issues-update-format-safe.test.sh`, `issues-description-file.test.sh` | `update.json` |
| `bulk-update` | `bulk-update-diagnostics.test.sh` | `bulk-update.json` |
| `activate` | `issues-activate-agent.test.sh`, `issues-activate-assignee.test.sh` | `activate.json` |
| `complete` | `issues-complete-summary.test.sh` | `complete.json` |
| `archive`, `trash` | `issues-archive-trash-entity-verify.test.sh` | `archive.json`, `trash.json` |
| `delete` alias | extend `action-aliases.test.sh` for the trash alias | reuse `trash.json`; no separate live capture claim |
| `add-relation`, `remove-relation` | extend `issues-add-relation-hierarchy.test.sh` for the paired removal contract | `add-relation.json`, `remove-relation.json` |
| `validate-completion` | `completion-validation-parented-root.test.sh`, `completion-validation-bundle-children.test.sh` | `validate-completion.json` |

**Dependencies**: pieces 1, 3, 5, 6 and 7; a new delegation that repeats the scratch-pair permission and permits cancellation cleanup on failure.

**Execution boundary**

- This is one live-recording lane because the pair and its cleanup share a lifetime. Do not split creation from cancellation across delegates.
- Run strict auth and verify target name `kendex`, key `KEN`, UUID `53d3175c-fcb0-49ce-9f82-286a5b77372e` before creation. Create only the two authorized scratch issues. No shared label definition or other live record changes.
- Record `create`, `update`, `bulk-update`, `activate`, `complete`, `add-relation`, `remove-relation` and `validate-completion` against that pair. Keep both top-level for peer relation tests. Use approved existing labels and file-based bodies.
- Complete and validate a scratch issue before canceling it. Keep KEN-2463 outside this piece. An activation failure remains a failure; it does not authorize a label-definition fix or activation of KEN-2335.
- Remove the test relation. Set both scratch issues to Canceled and read both back. Save cancellation receipts before destructive commands can hide them.
- Record archive on a canceled scratch issue and trash on the other canceled scratch issue. Prove `delete` through the existing alias owner and the same recorded trash contract. Do not claim a separate live delete capture if none ran.
- On failure, stop the remaining contract sequence. Preserve receipts and perform only the authorized scratch cleanup. If cleanup cannot finish, the parent owns the cancellation obligation and the lane does not report closure.
- Promote one redacted fixture per command under `tests/fixtures/recorded/contracts/issue-writes/`, named for the verb. The fixture's provenance distinguishes live mutation evidence from offline failure controls.

**Done-when**

- Every named issue-write family and completion validation has recorded replay assertions through its existing suite owner.
- Mutation output, entity verification, bulk partial-failure behavior and any requested reply connections retain their contracts. Must-fail chain controls reject incomplete requested replies without partial read results; any write already accepted is reported by its existing partial-write contract, not called rolled back.
- Both scratch identifiers and cancellation read-back receipts exist. Archive/trash receipts remain linked to those identifiers. No active scratch record is left.
- The parent names both identifiers and cancellation proof on KEN-2335 and in the PR body through its authorized reporting route. That report is not permission to mutate another record during capture.

**Closure evidence**: exact command/capture/fixture/suite/control table; both identifiers; cancellation receipts; destructive-command receipts; parent publication receipt. Current state is still “no scratch created,” not “write coverage passed.”

### 9. Caller migration, documentation and consumer proof

**Scope and existing owners**

| Owner | Files to audit or finish |
|---|---|
| Orch runtime callers | `skills/orch/scripts/branch-size-check`, `container-close`, `reconcile-work-items`, `oversee-report`, `lib/escapes.sh` |
| Hosted clone preparation | `skills/orch/scripts/lane-host-ssh`, `skills/orch/schemas/lane-host.md` |
| Caller tests | `skills/orch/tests/branch_size_check.sh`, `container_close.sh`, `reconcile-work-items.test.sh`, `lane-host-ssh.sh`, `lib/lane-host-ssh-tests.py`, `oversee_report_escapes.sh`; existing `lib/assertions.sh`, `lib/growth-state.sh` and embedded controls |
| Dev workflows | `skills/dev/workflows/dev-fix.md`, `dev-implement.md` |
| Orch workflows | `dev-start`, `handoff`, `merge-pr`, `micro`, `post-summary`, `review-pr`, `start-worktree`, `start`, `submit-pr` under `skills/orch/workflows/` |
| Project management | `skills/project-management/SKILL.md`, `references/dependencies.md`, `references/labels.md`, `schemas/roadmap-plan-input.md`, and the workflows listed in the caller map |
| Reviewer and queue consumers | `skills/reviewer/workflows/qa-review.md`, `skills/kendex-issues/SKILL.md` |
| Package explanation | `skills/linear/README.md`, `SKILL.md`, `DEVELOPMENT.md`, `patterns/workflow-actions.md`, recorded-fixture README |
| Hook/tool consumers | `hooks/`, tracked hook renders and `tools/`; audit named calls and store paths over the whole affected tree |

All shipped source changes include their tracked `.agents/skills/` or hook render partners. Tests and `DEVELOPMENT.md` have no skill render. Existing hook and tool test owners stay in use if the caller audit finds affected files.

**Change intent**

- Reuse the existing caller map and finish omissions. Preserve exact old/new forms for every removed verb or store path in PR handoff material, including a deletion with no replacement.
- Fix the known stale `branch_size_check.sh` stand-in. It still requires `cache issues get` and reads `.cache/linear/issues.json`, while production calls `issues get ID --format=raw`. Use an isolated live-response fixture, correct positional arguments and the existing assertions/controls.
- Strengthen hosted-clone proof by planting a source `.cache/linear` fixture that the provider must not copy. The present no-cache assertion starts without that source data and cannot establish that copying was removed. Keep `.env.local` transfer and unrelated kendex lock isolation proved.
- Keep the migrated reconcile and escapes tests. Prove failed live inventory reads refuse rather than report a clean scan or zero escapes. Use their existing embedded mutation controls.
- Correct instruction errors shown in the caller map: duplicated `[PROJECT_ID]` in dependency-read examples, lost GitHub skip around the TPM team lookup, and omitted live label preflight in `linear/patterns/workflow-actions.md`. Require `--max` wherever a former cache inventory supplied all rows. These are caller contract corrections, not a new planning workflow.
- Remove stale sync headings, cache-repair instructions and no-sync brief premises. Keep tracker routing and GitHub-only runs free of Linear requirements.
- Update consumer-facing fragments through `changelog.d/README.md`. The existing `changelog.d/removed/KEN-2335-linear-store.md` combines removal, attachment behavior and quota output. Give each consumer-visible change its own fragment, with one item within the owner limit of 200 characters.

**Dependencies**: pieces 2 through 7 supply the retained output and failure contracts. Piece 8 supplies lifecycle proof for completion consumers. Documentation audit can start earlier; closure needs those contracts.

**Done-when**

- No active caller invokes a removed verb or reads a Linear store path. Removed-command refusal tests and migration notes are identified separately from active calls.
- Caller suites and their controls pass, including branch size, container closure, reconcile, hosted SSH and escapes. Hook/tool checks selected by existing metadata have receipts.
- The PR handoff contains exact old/new forms, paired-render scope, retired settings and all owner-authorized cuts. It does not copy private tracker bodies.
- Consumer status stays cleared: fleet FLT-641 merged at `97f82a8278011ca5166bee27ae5a1843dafe4fab`; vg files nothing; VGS-719 follows release and does not gate merge. Do not reopen consumer work from the stale caller-map footer.

**Closure evidence**: whole-tree caller inventory and reviewed exclusions; exact-form PR appendix; caller suite/control receipts; documentation and fragment diffs; existing consumer clearance references. No architecture document change is required: API entry point, transport and ownership stay unchanged.

### 10. Integrated validation and parent closure handoff

**Scope and owners**: `tools/guard`, `tools/ci-job-set`, `.agents/skills/orch/scripts/dev-validate-run`, existing preflight/doc-limits tools, orch return-artifact owner and parent review/PR workflow. No runner or settings change.

**Dependencies**: all prior pieces have their closure evidence. A new owner delegation authorizes this gate.

**Validation intent**

- Run affected suites and controls once through the required runners. The Linear set includes new replay assertions plus blocker, OAuth, retirement, quota and issue-write owners. Caller proof includes reconcile, SSH and escapes as explicitly required, not only whatever a narrow source grep selects.
- Run preflight and doc-limits once. A document-ceiling failure needs an actual trim or split in a later authorized piece, not a blind rerun.
- Run configured range validation through `dev-validate-run --worktree` with range mode and the parent-bound base. `kendex.settings.toml` sets `DEV_VALIDATE_RANGE_CMD` to `tools/guard --range $DEV_VALIDATE_BASE`; full validation is `tools/guard --full` where the parent-authorized normal cycle requires it.
- The range must include the committed migration and caller changes, not only new edits after `d19e004...`. Bind the base to the original change range. The initial owner brief records `42597eb5111883b740eb41a1af59e9c71d4cf309` as the pre-dev HEAD. The parent verifies the base binding before execution.
- Let existing selection owners include direct and indirect dependencies. Unreadable or unmapped selection uses their whole-area fallback. Add no custom selector.
- Unset `TMPDIR` and `ORCH_STATE_DIR` for recording, test and validation jobs. State stays under this worktree's `tmp/`; use an absolute `--state-dir` where supported.
- Preserve run directory, mode, base, HEAD, command, log, exit, timing and runner receipt. A started or interrupted job has no passing verdict.
- KEN-2464 `release_workflow::catalog` alone may use the external-validation exception. Record its exact failure and CI proof obligation. It is not a green local run. Every other failure holds the round. No exception receipt currently exists.

**Done-when**

- Every required contract maps to shipped replay assertions and passing suite/control receipts, or to the exact authorized cut below. Audit the retained command inventory against that matrix, including existing fixtures for commands outside the open-capture tables. Any uncovered retained contract stays a named blocker; it is not silently added to the recording permission.
- Preflight, doc-limits and configured validation have bound receipts. Any external exception is named separately. All other checks pass on the candidate tree.
- Source/render pairs and consumer fragments are ready for an authorized commit. Preserve reported commits; do not rebase or amend them.
- The parent receives the valid return artifact, exact PR appendix, scratch cleanup proof and cut table. The normal cycle permits one blockers-only review round after authorization. Parent owns review, push, PR creation and merge.

**Closure evidence**: the complete contract matrix; all runner receipts; valid return artifact; reviewed source/render pairing; PR handoff. Until this evidence exists, KEN-2335 remains blocked. A smaller piece passing does not override a failed integration receipt.

## Authorized cuts

New recorded mutation fixtures for these non-issue verbs belong to KEN-2477. Keep the verbs, existing suites and existing fixtures. Do not use this cut to omit read capture promotion or regression checks selected by the affected dependencies.

| Resource | Cut from new mutation recording |
|---|---|
| `comments` | `create`, `update`, `delete` |
| `labels` | `create`, `update`, `delete` |
| `project-labels` | `create`, `update`, `delete` |
| `projects` | `create`, `update`, `delete`, `add-dependency`, `remove-dependency`, `post-update`, `reorder`, `set-sort-order` |
| `initiatives` | `create`, `update`, `delete`, `add-project`, `remove-project` |
| `milestones` | `create`, `update`, `delete` |
| `cycles` | `create`, `update` |

`documents`, `teams`, `users` and `statuses` have no retained mutation verbs in this cut. KEN-2463 remains the known activation-label defect outside scope. The personal-key initiative exception permits recording only. Neither exception permits an auth-mint scope change.

## File impact

- **Files to modify after authorization**: page reader and paired render; attachment and session command payload joins and paired renders; existing replay/assertion/control files; existing issue-write and regression suites; caller files and partners named in piece 9; package explanation, settings comment and consumer fragments.
- **New files after authorization**: redacted contract fixtures at the exact paths in pieces 2 through 5; issue-write fixtures under `skills/linear/tests/fixtures/recorded/contracts/issue-writes/`; separate consumer fragments under `changelog.d/`. No new production module, selector or runner.
- **Critical execution files**: `skills/linear/scripts/lib/pages.sh`, `skills/linear/scripts/lib/common.sh`, `skills/linear/tests/lib/assert.sh`, `skills/linear/tests/live-resource-pages.test.sh`, `tools/guard`.
- **This planning task's only repository write**: `docs/plans/linear-store-removal-remaining-work.md`. No production, test, configuration, render or other documentation edit belongs to this task.

## Consequences and rollback

| Risk and likelihood | Mitigation |
|---|---|
| Another response-sized join fails after the page fix. The page and command owners contain several such joins; runtime frequency is unknown. | Repair the class at each existing owner. Exercise single-page, accumulated, nested and command-final assembly paths. |
| A closed capture appears to prove continuation. This is the current attachment evidence gap. | Keep captured rows and derived pagination controls distinct. Require complete and partial-chain assertions. |
| Redaction breaks relation endpoints or bulk identities. Likelihood is unknown; the earlier fixture generator collapses identifiers. | Use a consistent distinct identifier map across request/reply references. Assert expected identifiers independently. |
| A scratch issue remains active after a failed write. This becomes possible only after future scratch creation. | Keep pair ownership and cleanup in one lane. Save cancellation proof before archive/trash. Report any cleanup obligation to the parent. |
| A narrow check misses a migrated caller. This is a known risk: the branch-size stand-in still uses removed forms. | Use the whole-tree caller map plus existing dependency selection and explicit mandatory suites. |
| Private cookies or tracker text enter fixtures. Capture headers contain cookies. | Promote body/request JSON only after redaction. Keep raw headers and private bodies under `tmp/`. |

- **Owned-skill report**: the Linear skill is kendex-owned. The parent routes the page-reader defect through `kendex report` only after authorization. This plan makes no report or tracker write.
- **Rollback before integration**: keep the branch held and preserve captures, reported commits and the attachment pair. A failed piece does not permit automatic cleanup, retry or reset. Scratch cancellation remains the explicit cleanup obligation in piece 8.
- **Rollback of later authorized code**: parent authorizes a revert of the new piece's commit, with its source/render and fixture partners together. Do not reset to the migration base or restore a cache as a workaround.
- **Rollback after release**: parent coordinates a revert or forward fix under the normal release process. Exact caller forms in the PR appendix show the affected consumers. This plan does not authorize release or consumer writes.

## TPM handoff prompt

A TPM handoff is needed only to represent separately tracked remaining pieces. Issue filing, project placement and backlog order are not technical-plan work. KEN-2477 already owns the non-issue recording cut; do not create a duplicate.

> Read `docs/plans/linear-store-removal-remaining-work.md` and the bound KEN-2335 owner receipts. Return an audit and tracking proposal for the technical pieces. Keep the shared page repair ahead of dependent replay and live recording work. Keep scratch creation, all issue-write captures and cancellation in one tracked lane. Preserve the existing migration and dirty attachment pair. Keep KEN-2477, KEN-2463 and the exact KEN-2464 exception separate. The consumer gate is cleared. Recommend existing items or narrowly scoped child items with the plan's Done-when and closure evidence. Do not file or move issues until the owner authorizes the tracking proposal. Do not create a roadmap or reinterpret the technical scope.

## Implementer handoff prompt

> Execute only the piece named in a new owner-approved delegation from `docs/plans/linear-store-removal-remaining-work.md`. Read its evidence and prerequisites first. Work only in `/home/dev/dev/.worktrees/kendex/ken-2335`. Preserve HEAD `d19e00429c1d1fde61947543ee6840877436ef68` and the attachment source/render correction as the starting state. Keep `linear.sh`, `graphql_request`, the page owner, existing assertions, controls and validation runners. Do not add a client, service, MCP route, selector or runner. Distinguish capture, shipped replay and passing proof in the return. Use the required job route and keep state under this worktree's `tmp/`. No sync, refresh, apply, base checkout or lock writes. Live issue-write recording is limited to the authorized scratch pair and includes cancellation proof before lane end. No other live record changes, shared-label changes or mint-scope changes. Stop on a new failure and preserve its receipt. Follow only the delegated cleanup and quota rules. Return exact files, Done-when evidence and any remaining blocker to the parent. Parent owns commits when authorized, review, push and PR actions. This plan itself authorizes none of those actions.
