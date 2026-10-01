#!/usr/bin/env bash
# `issues create --attach <PATH>` uploads local files through
# Linear's fileUpload flow (mutation -> PUT to uploadUrl with EXACTLY the
# returned headers) and references them from the created issue: images embed
# as ![name](assetUrl) in the description, other files become Linear
# attachments via attachmentCreate after the create.
#
# Fail-loud contract under test: a missing/unreadable path refuses before
# any API call; a PUT failure refuses before the issue exists; an
# attachmentCreate failure AFTER the create reports the created identifier
# with partial: true and exits non-zero.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
assert_tmpdir TMP_ROOT

PROJECT="$TMP_ROOT/project"
mkdir -p "$PROJECT/.agents/skills" "$PROJECT/bin"
git -C "$PROJECT" init -q -b main
cp -R "$SKILL_DIR" "$PROJECT/.agents/skills/linear"

LINEAR="$PROJECT/.agents/skills/linear/scripts/linear.sh"
CURL_LOG="$TMP_ROOT/curl-payloads.jsonl"
ERR_FILE="$TMP_ROOT/stderr.txt"

# The fake curl mirrors the script's two transports: GraphQL POSTs and the
# storage PUT arrive as curl-config-on-stdin (-K -). Asset downloads use the
# same transport and pass their output and header paths as direct arguments.
cat >"$PROJECT/bin/curl" <<'SH'
#!/usr/bin/env bash
has_config=0
for a in "$@"; do [ "$a" = "-K" ] && has_config=1; done
if [[ "$has_config" = "0" || "$*" == *' -D '* ]]; then
  if [[ "$has_config" = "1" ]]; then cat >/dev/null; fi
  if [ "${FAKE_ASSET_DOWNLOAD:-0}" = "fail" ]; then
    printf '500'
    exit 0
  fi
  if [ "${FAKE_ASSET_DOWNLOAD:-0}" = "1" ]; then
    out="" headers=""
    while (($#)); do
      case "$1" in
      -o) out="$2"; shift 2 ;;
      -D) headers="$2"; shift 2 ;;
      *) shift ;;
      esac
    done
    printf 'research findings\n' >"$out"
    printf 'HTTP/2 200\n' >"$headers"
    printf '200'
    exit 0
  fi
  # background attachment-cache download — out of scope until the sync case
  printf '404'
  exit 0
fi
config="$(cat)"

if grep -q '^upload-file = ' <<<"$config"; then
  url="$(sed -n 's/^url = //p' <<<"$config" | jq -r)"
  file="$(sed -n 's/^upload-file = //p' <<<"$config" | jq -r)"
  headers="$(sed -n 's/^header = //p' <<<"$config" | jq -s .)"
  jq -cn --arg url "$url" --arg file "$file" --argjson headers "$headers" \
    '{put: {url: $url, file: $file, headers: $headers}}' >>"${CURL_LOG:?}"
  case "$file" in
  *put-fail*) printf '500' ;;
  *) printf '200' ;;
  esac
  exit 0
fi

payload="$(sed -n 's/^data = //p' <<<"$config" | jq -r)"
printf '%s\n' "$payload" >>"${CURL_LOG:?}"
query="$(jq -r '.query' <<<"$payload")"

case "$query" in
*"fileUpload("*)
  filename="$(jq -r '.variables.filename' <<<"$payload")"
  printf '%s' "{\"data\":{\"fileUpload\":{\"success\":true,\"uploadFile\":{\"uploadUrl\":\"https://uploads.linear.app/put/$filename\",\"assetUrl\":\"https://uploads.linear.app/asset/$filename\",\"headers\":[{\"key\":\"x-linear-upload\",\"value\":\"signed-$filename\"},{\"key\":\"x-amz-acl\",\"value\":\"private\"}]}}}}___HTTP_CODE___200"
  ;;
*"attachmentCreate("*)
  title="$(jq -r '.variables.input.title' <<<"$payload")"
  if [ "$title" = "boom.pdf" ]; then
    printf '%s' '{"data":{"attachmentCreate":{"success":false,"attachment":null}}}___HTTP_CODE___200'
  else
    printf '%s' '{"data":{"attachmentCreate":{"success":true,"attachment":{"id":"att-uuid","url":"u","title":"t"}}}}___HTTP_CODE___200'
  fi
  ;;
*"SyncIssueAttachments"*)
  printf '%s' '{"data":{"attachments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"url":"https://uploads.linear.app/asset/findings.md","title":"docs/research/TEAM-1/findings.md","issue":{"identifier":"TEAM-1"}}]}}}___HTTP_CODE___200'
  ;;
*"teams(filter:"*)
  printf '%s' '{"data":{"teams":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"team-uuid"}]}}}___HTTP_CODE___200'
  ;;
*"issueLabels(filter:"*)
  name="$(jq -r '.variables.name // empty' <<<"$payload")"
  if [ "$name" = "agent:ghost" ]; then
    printf '%s' '{"data":{"issueLabels":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}___HTTP_CODE___200'
  else
    printf '%s' '{"data":{"issueLabels":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"label-uuid"}]}}}___HTTP_CODE___200'
  fi
  ;;
*"issueCreate(input:"*)
  title_in="$(jq -r '.variables.input.title // empty' <<<"$payload")"
  if [ "$title_in" = "REJECT-CREATE" ]; then
    printf '%s' '{"data":{"issueCreate":{"success":false,"issue":null}}}___HTTP_CODE___200'
    exit 0
  fi
  printf '%s' '{"data":{"issueCreate":{"success":true,"issue":{"id":"issue-uuid","identifier":"TEAM-1","title":"t","description":"","state":{"name":"Todo","type":"unstarted"},"assignee":null,"project":null,"projectMilestone":null,"cycle":null,"parent":null,"team":{"name":"Configured"},"labels":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"priority":3,"estimate":null,"sortOrder":1.0,"url":"https://linear.app/x/issue/TEAM-1","createdAt":"2026-08-08T00:00:00Z","updatedAt":"2026-08-08T00:00:00Z","archivedAt":null,"trashed":null,"relations":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"inverseRelations":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}___HTTP_CODE___200'
  ;;
*)
  printf '%s' '{"data":{}}___HTTP_CODE___200'
  ;;
esac
SH
chmod +x "$PROJECT/bin/curl"

printf '[env]\nLINEAR_TEAM = "Configured"\n' >"$PROJECT/kendex.settings.toml"

printf 'PNGDATA' >"$TMP_ROOT/shot.png" # 7 bytes, image/png
printf '%%PDF-1.4' >"$TMP_ROOT/notes.pdf"
printf '%%PDF-1.4' >"$TMP_ROOT/second.pdf"
printf 'x' >"$TMP_ROOT/boom.pdf"
printf 'x' >"$TMP_ROOT/put-fail.png"
printf 'Body from file.' >"$TMP_ROOT/desc.md"
mkdir -p "$PROJECT/docs/research/TEAM-1"
printf 'Research notes.' >"$PROJECT/docs/research/TEAM-1/findings.md"

OUT=""
ERR=""
RC=0

# assert_log DESC FILTER — FILTER must select a true value over the logged
# curl payloads, read as a stream.
assert_log() {
  assert "$1" jq -s -e "$2" "$CURL_LOG"
}

assert_not_log() {
  assert_not "$1" jq -s -e "$2" "$CURL_LOG"
}

run_linear() {
  : >"$CURL_LOG"
  RC=0
  OUT="$(cd "$PROJECT" && env -u LINEAR_TEAM -u LINEAR_AGENT_LABELS \
    PATH="$PROJECT/bin:$PATH" \
    LINEAR_API_KEY=test-token \
    CURL_LOG="$CURL_LOG" \
    bash "$LINEAR" "$@" </dev/null 2>"$ERR_FILE")" || RC=$?
  ERR="$(cat "$ERR_FILE")"
}

api_calls() {
  wc -l <"$CURL_LOG" | tr -d ' '
}

echo "=== image attach: fileUpload -> PUT with returned headers -> embed in description ==="

run_linear issues create --title "With image" --attach "$TMP_ROOT/shot.png"
assert_eq "an image attach create exits zero" "$RC" 0

assert_log "fileUpload carries the contentType, filename and size read from the file" \
  'any(.[]; (.query? // "" | contains("fileUpload"))
    and .variables.contentType == "image/png"
    and .variables.filename == "shot.png"
    and .variables.size == 7)'

assert_log "the PUT carries the returned headers plus Content-Type" \
  'any(.[]; .put?.url == "https://uploads.linear.app/put/shot.png"
    and (.put.headers | index("x-linear-upload: signed-shot.png"))
    and (.put.headers | index("x-amz-acl: private"))
    and (.put.headers | index("Content-Type: image/png")))'

