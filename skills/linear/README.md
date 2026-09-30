# Linear CLI

A shell CLI for Linear issues, projects and planning data. It includes a local cache for reads and sends changes to the Linear API.

## Install

```bash
kendex add vanillagreencom/kendex --skill linear
```

Requires Bash 4.0 or newer, curl, jq and flock. Set `LINEAR_API_KEY` and `LINEAR_TEAM` in the kendex app, on this package's Customize tab: the key goes to the project's private env file and the team to `kendex.settings.toml`. Both can be set by hand instead. Run the installed `scripts/linear.sh auth-check --strict`, then `scripts/linear.sh sync --reconcile`.

## Features

- Read and change issues, projects, comments and planning data.
- Refresh a local cache for repeated reads.
- Report request counts by caller and warn when a caller exceeds its hourly share.
- Upload and download attachments.
- Check configured issue requirements during creation and completion.

## How it works

You configure the API key and target team. A sync downloads Linear data into the project's local cache. Cache commands read that saved data. Write commands send changes to Linear and update the cache.

## Request usage

`linear.sh usage` reads `.cache/linear/requests.jsonl` without an API call. It reports a trailing hour and the observed journal age. Each retry adds a request. Equal shares divide the budget across caller identities seen in that hour. The command rows show each resource and action. API answers read only the active-hour snapshot in `.cache/linear/requests-active.json`. This snapshot starts with the first request when it is absent. The durable journal keeps older requests for reports and lane archives. The request function warns on an exceeded share or low server Remaining. A warning does not block a request. Rate-limit errors include the server reset time in UTC epoch milliseconds; a missing header produces `null`.

Requests and sync refuse an isolated managed cache at a linked-worktree root before contacting Linear. The cache must resolve to the main checkout's cache. Sharing `.cache` or its `linear` child meets this rule. Repair the worktree links named in the error. A set `WORKTREE_SYMLINKS` that excludes `.cache`, including an empty value, selects local caches. `LINEAR_CACHE_ROOT` selects the cache root; a redirect outside the managed worktree cache is independent.

[Linear documents](https://linear.app/developers/rate-limiting) that API keys for the same authenticated user share one request quota. Repositories using that user must divide one budget between them. Set `LINEAR_HOURLY_BUDGET` to each repository's allocation. Journals measure only requests made through this skill and cache root. They cannot identify another repository's traffic or establish its user identity. Remaining is the server's shared balance, not a local count.

Run `sync --reconcile` once at lane preflight. Round refreshes use `sync --if-stale 15`. Incremental sync does not reconcile deletions made outside the CLI.

## Settings

Set non-secret keys in committed `kendex.settings.toml` under `[env]`; the key list with each default and what leaving it unset means is [kendex.settings.toml.example](kendex.settings.toml.example).

| Variable | Purpose |
|----------|---------|
| `LINEAR_API_KEY` | The API key, in the project's private env file |
| `LINEAR_TEAM` | The team every write targets; required |
| `LINEAR_TEAM_PREFIX` | Issue identifier prefix used in examples |
| `LINEAR_AGENT_LABELS` | Agent-routing labels an `issues create` must carry one of |
| `LINEAR_REQUIRE_REACH` | Non-empty enforces the `Reached by:` and `Symptom:` lines at create |
| `LINEAR_FORMAT` | Default read format: `safe`, `table`, `ids`, `raw` |
| `LINEAR_RETRY_BASE_DELAY` | Seconds before the first retry of a failed call, doubling after |
| `LINEAR_HOURLY_BUDGET` | Repository hourly request allocation; empty uses the reported request limit |
| `LINEAR_CACHE_ROOT` | Overrides the cache root for one invocation; refused if it names no directory |
| `KENDEX_USER_EMAIL` | Your email address, in the project's private env file; `issues activate` assigns an unassigned issue to the Linear user with that address |

`KENDEX_USER_EMAIL` is kendex's own setting, not this skill's: the app's Customize tab writes it to the private env file (`.env.local` unless `KENDEX_ENV_FILE` names another), never to `kendex.settings.toml`. Use the address your Linear account signs in with; it is matched whole and without regard to case. Empty or absent assigns nobody. A worktree whose `WORKTREE_SYMLINKS` lists `.env.local` links that file to its main checkout, and a hosted lane receives a copy of the checkout's `.env.local` each time it is created, so a value set there reaches every lane of that checkout. A value exported only in the shell that starts the lanes does not: a local lane's tmux pane takes its environment from the tmux server, not from that shell.
