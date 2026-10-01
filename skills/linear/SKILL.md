---
name: linear
description: "Load for any Linear read or write: issues, projects, cycles, milestones, initiatives, labels."
summary: "Bash CLI over Linear's official GraphQL API: read, search, create, or update issues, projects, cycles, milestones, initiatives, and labels."
license: MIT
user-invocable: true
metadata:
  author: vanillagreen
  source: kendex
  repository: "https://github.com/vanillagreencom/kendex"
  bugs: "https://github.com/vanillagreencom/kendex/issues"
  version: "1.1.0"
tags: [integration]
---

# Linear CLI

```bash
.agents/skills/linear/scripts/linear.sh <resource> <action> [options]
```

Reads and writes use Linear's official GraphQL API. No tracker data or OAuth token is stored locally. `linear.sh <resource> --help` prints per-resource options. `--format` values: `safe` (the default, flat and null-safe), `compact` (a smaller shape for workflow routing), `ids` (identifiers only), `table`, `raw` (the GraphQL nesting, so never assume top-level jq paths). `safe` renames fields: `identifier`→`id`, `id`→`uuid`, `state.name`→`state`, `state.type`→`state_type`, `sortOrder`→`sort_order`.

## Commands

| Resource | Actions |
|----------|---------|
| `issues` | list, get, bulk-get, create, update, bulk-update, archive, trash/delete, children, list-relations, add-relation, remove-relation, activate, block, unblock, complete, validate-completion |
| `comments` / `labels` / `project-labels` | list, create, update, delete |
| `projects` | list, get, create, update, delete, list-dependencies, add-dependency, remove-dependency, post-update, list-updates, reorder, set-sort-order |
| `initiatives` / `milestones` | list, get, create, update, delete (`initiatives` also add-project, remove-project) |
| `teams` / `users` / `statuses` / `documents` | list, get (`users` also has `me`; `teams keys` reads `{urlKey, keys}` for outbound tracker links without changing `teams list`'s array) |
| `cycles` | list, create, update |
| `auth-check` | Report the selected credential, actor, team and `writes_enabled` (`--strict` exits non-zero when writes would refuse) |
| `auth-mint` | Mint application token JSON from the client pair without writing files |
| `attachments` | list, fetch |
| `session-status` | Aggregated status for the `/start` workflow |

Aliases: `issues relations` → `list-relations`, `projects dependencies` → `list-dependencies`. Singular resource names (`issue`, `project`, …) route to the plural. There is no `view`/`show`: single-issue lookups are `issues get <ID>` (live); only the live `issues get <ID>`, without `--with-bundle` and in the default `safe` format, carries `github_sync`, the GitHub issues Linear's GitHub sync links the issue to, each as `owner/repo#N` lowercased. Multi-issue lookups are `issues bulk-get <ID1> <ID2> ...`, which is also the post-mutation verification path. Comments for several issues are one `comments bulk-list <ID1> <ID2> ...` call (`--stdin` takes one identifier per line), never a loop or parallel `comments list` readers.

Schema reference over ctx7: `/websites/studio_apollographql_public_linear-api_variant_current` (API), `/linear/linear` (SDK), `/websites/linear_app_developers` (guides). [patterns/workflow-actions.md](patterns/workflow-actions.md) covers multi-step state changes.

## Live reads

Use `--max` for full inventories. Issue and project listings keep their bounded defaults. Metadata listings also accept `--max`. A failed page chain returns nonzero without partial output.

`issues list --all-projects` selects every project. `--no-project` selects unassigned issues. Both refuse use with `--project`. Repeated `--label` values require every named label.

Removed `sync` and `cache` verbs print the live replacement and exit nonzero.

## Team Target

`LINEAR_TEAM` has no default. With it unset every write refuses before any API call; reads drop the team filter. `--team <name>` overrides per call only on `issues create`, `projects create`, `cycles create`, and `labels create`. Run `auth-check --strict` before the first mutation in a project.

Set `LINEAR_APP_TOKEN` or the client pair in the project's private env file (`.env.local` unless `KENDEX_ENV_FILE` names another); `op://` references are supported. Use `auth-mint` on the host with the real pair to publish a token to the fleet. Credential precedence, expiry, caching and attribution: [README.md § Settings](README.md#settings).

`LINEAR_API_KEY` and `KENDEX_USER_EMAIL`, the operator's email, also belong in the private env file. Non-secret defaults belong in committed `kendex.settings.toml` `[env]`. The kendex app's Customize tab writes the key, team and email. A `LINEAR_API_KEY` from project files beats an inherited key. When the personal key is selected, `auth-check` warns with fingerprints if it shadows a different inherited key. Every other key uses process environment precedence over the private env file.

## Shared label maintenance

`LINEAR_TEAM` requires a target before writes; it does not restrict an API key or check a label's owning team. `auth-check` verifies authentication and the local target, not the key's permission mask. Inspect key permissions in Linear settings; report fingerprints only.

Before changing a label definition, read its ID, team, parent and group status. An empty team means workspace scope. Read issue use across affected teams and check references in their manifests, scripts, gates and generated instructions. A team-restricted key cannot establish workspace-wide issue use.

The workspace owner coordinates shared label changes with affected repository maintainers. A repository taxonomy names that owner. Keep generic labels shared and project-specific labels team-scoped. Obtain approval for the concrete affected set and the exact proposed change before any shared-label definition change, replacement or deletion. Issue-label assignment authority does not authorize changing a shared label definition.

Prepare dependent repository corrections before the label change. After an authorized change, refresh each affected inventory, render instructions from their source, and run its taxonomy and repository checks. Record the label IDs, issue assignments and repository commits together. If the API cannot change scope, prepare a replacement plan with history and recovery limits before requesting migration approval.

## Issue Creation Routing

Never create a tracked issue directly from an orchestration or review session. Route it through the TPM pipeline (project-management skill), which owns labels, project, priority, estimate, and relations.

Where `LINEAR_AGENT_LABELS` declares a taxonomy, `issues create` refuses before any API call a create with no agent label from that set (`--no-agent-label` permits a deliberate bare create). Where `LINEAR_REQUIRE_REACH` is set, it refuses a description with no `Reached by:` line and, with `--review-born` and `--priority 2`, one with no `Symptom:` line; a placeholder or null token counts as no line. Each guard is its own setting. What the lines say is the author's to judge; the rule is the project-management skill's SKILL.md § Disposition, **Name what reaches it**, which is also where a create decides whether it is review-born.

## Attachments

`issues create`, `issues update`, and `comments create` take a repeatable `--attach <path>`. Images embed as markdown in the description/body. On `issues update` without `--description`, the embed appends to the existing description rather than replacing it. Other files become Linear attachments on issues, or markdown links on comments (comments have no attachment surface). An unreadable path refuses before any API call; an attachment failure after a successful issue write reports `partial: true` and exits non-zero.

`issues create` and attach-only `issues update` report `attachments_requested`, the number of non-image records requested, and `attachments`, one `{url, repo_path}` object per record in request order once every `attachmentCreate` succeeded. On `issues create` they appear in the default JSON response only, so a create that needs this verification takes the default output: `--format=ids` prints the identifier alone and discards both fields. Those fields are the immediate verification. `attachments list` reads the live records to verify a just-written attachment.

### Resolve a cited artifact

Read the cited repository path when it exists. Otherwise run `linear.sh attachments list [SOURCE_ISSUE_ID]`. Match `repo_path` within that issue. Use a unique filename only when no repository path exists. Use the cited URL to select among versions. An ambiguous match requires clarification.

Fetch the selected URL with `linear.sh attachments fetch [URL] --output tmp/[FILE]`, then read that file. Keep the repository reference and source issue in tracker text and cross-checkout briefs. Resolve companion files the same way. An API or download failure stops the workflow; it is not an absent artifact.

## Blocked Label vs Issue Relations

A blocker that is itself a Linear issue is a relation (`--blocked-by`); an external one (vendor, license) is the `blocked` label plus a comment.

Blocking relations must connect peers of one bundle: same direct parent, or both top-level. The two issues need not share a project. An issue cannot block its own ancestor or descendant; use `--related` for traceability. The check reads each issue's own direct parent in one query.

A blocking relation pointing at a Done or Canceled issue is **satisfied history, not stale metadata**. The relation stays for provenance; never remove or "fix" it, and audits must never classify it as stale. The only legitimate audit output for a completed-blocker relation is a scheduling signal ("gates cleared, ready to schedule").

Normalized issue lists, gets, bulk gets, bundles, recursive children, relation reads, and session status keep each blocking relation in `blocked_by` and list only nonterminal blockers in `blocked_by_open`.

## Option Behavior

What each option accepts: `issues --help`. Refused before any write, on the create and update paths alike: `--cycle` on a non-UUID, `--project`/`--milestone`/`--assignee` on a reference that matches nothing, and `--priority` on an out-of-range value. Available states: Backlog, Todo, In Progress, In Review, Done, Canceled (not "Cancelled"). Verify with `statuses list`.

A **name** selects one project on `issues create` / `update` / `bulk-update --project`, `projects get`, `projects list-dependencies`, `milestones --project`, and `initiatives add-project` / `remove-project`. There a canceled project sharing that name loses to the live one, and a name with no live match is refused, naming each match and its state; pass a UUID to reach a canceled project. Name **filters** never resolve: `issues list --project` and `documents list --project` match on the name alone, so their results can mix a live project with its canceled twin.

`--labels` REPLACES the whole issue-label set. Fetch current labels, compute the final set, validate it against `labels list --format=safe` (which reports `is_group` so parent/group labels can be rejected), then pass the complete set. A name that does not resolve fails the update; `--clear-labels` is the only way to empty the set.

- `agent:*` labels are mutually exclusive, one per issue; `issues activate` applies them with the "In Progress" transition (semantics: `issues --help`).
- `issues activate` assigns an issue nobody is assigned to the user whose email is `KENDEX_USER_EMAIL`, in the same mutation, and never replaces an assignee. It says which happened in one stderr line, `assignee-set`, `assignee-kept` or `assignee-skipped` with its `cause=`, and in the result's `assignee` field; a skip still activates, and a failed issue read, users lookup or update fails the activation with no line (lines: `issues --help`). `--assignee` on create and update takes the same address form: a value containing `@` matches a user's whole email, case-insensitively; a user id is sent as given.
- `issues bulk-update` is non-atomic: on partial failure it emits `partial: true` with per-issue results and exits non-zero.
- `issues block` applies the `blocked` label, creates the blocking relation, and comments. A rejected relation fails the command.

## validate-completion

The pre-merge check on state plus summary comment, live only: `issues validate-completion`, with no `cache` spelling. The expected-state matrix is in `issues --help` § Validate-Completion: session root vs bundle children vs `--container` parents, and the fail-closed flag pairing.

A "labelIds not exclusive child labels" error means two labels from one exclusive group. Requires Bash 4.0+ (macOS system Bash 3.2 is unsupported), `curl`, and `jq`.
