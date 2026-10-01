#!/bin/bash
# Live attachment inventory and explicit downloads. No local manifest.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
show_help() {
    cat <<'EOF'
Attachments
Usage: linear.sh attachments list <issue-id>
       linear.sh attachments fetch <url> --output <path>
List reads all issue attachment records and Markdown links in the issue and comments.
Fetch writes only the requested file. No download inventory is retained.
EOF
}
case "${1:-help}" in help|--help|-h) show_help; exit 0 ;; esac
source "$SCRIPT_DIR/../lib/common.sh"

list_attachments() {
    local ref="${1:-}" id result records issue comments links
    [[ -n "$ref" ]] || { echo 'linear-attachments: missing=issue-id' >&2; return 1; }
    id=$(resolve_issue_id "$ref") || return 1
    local query='query IssueAttachments($id: String!, $after: String) {
        issue(id: $id) {
            attachments(first: 50, after: $after) {
                pageInfo { hasNextPage endCursor }
                nodes { id url title issue { identifier } }
            }
        }
    }'
    local variables
    variables=$(jq -cn --arg id "$id" '{id: $id}') || return 1
    result=$(graphql_pages "$query" "$variables" issue.attachments) || return 1
    records=$(jq -c '[.issue.attachments.nodes[] | {id, url, source: .issue.identifier,
        context: "attachment", filename: (.title | split("/") | last),
        repo_path: (if (.title | contains("/")) then .title else null end)}]' <<<"$result") || return 1
    issue=$("$BASH" "$SCRIPT_DIR/issues.sh" get "$ref" --format=raw) || return 1
    comments=$("$BASH" "$SCRIPT_DIR/comments.sh" list "$ref" --format=raw) || return 1
    links=$(jq -cn --arg ref "$ref" --argjson issue "$issue" --argjson comments "$comments" '
        [({text: $issue.issue.description, context: "description"}),
         ($comments.issue.comments.nodes[] | {text: .body, context: "comment"})] |
        [.[] | .context as $context | (.text // "") |
         match("https://uploads\\.linear\\.app/[^\\s)>\"]+"; "g").string |
         {url: ., source: $ref, context: $context, filename: (split("/") | last), repo_path: null}]') || return 1
    jq -cn --argjson records "$records" --argjson links "$links" '
        $records + [$links[] | .url as $url | select(all($records[]; .url != $url))] | unique_by(.url)'
}

fetch_attachment() (
    local url="${1:-}" output='' authorization quoted temp code
    shift || true
    [[ "${1:-}" == --output && -n "${2:-}" && "$#" == 2 ]] || {
        echo 'linear-attachments: missing=--output' >&2; return 1;
    }
    output="$2"
    # Linear hosts authenticated assets here. Refuse a foreign URL before
    # sending an application credential to its server.
    [[ "$url" == https://uploads.linear.app/* ]] || {
        echo 'linear-attachments: refused=asset-host' >&2; return 1;
    }
    authorization=$(linear_authorization) || return 1
    quoted=$(curl_config_quote "Authorization: $authorization") || return 1
    temp=$(mktemp "${output}.XXXXXX") || return 1
    trap 'rm -f -- "${temp:?}"' EXIT
    local url_quote renewed=0
    url_quote=$(curl_config_quote "$url") || return 1
    while true; do
        code=$(printf '%s\n' "url = $url_quote" "header = $quoted" |
            curl -s -w '%{http_code}' -o "$temp" -K -) || return 1
        if [[ "$code" == 401 && "$LINEAR_AUTH_KIND" == app && "$renewed" == 0 ]]; then
            authorization=$(linear_authorization renew) || return 1
            quoted=$(curl_config_quote "Authorization: $authorization") || return 1
            renewed=1
            continue
        fi
        [[ "$code" == 200 ]] || { printf 'linear-attachments: download-http=%s\n' "$code" >&2; return 1; }
        break
    done
    mv -- "$temp" "$output" || return 1
    jq -cn --arg path "$output" '{local_path: $path}'
)

action="$1"
shift
case "$action" in
list) list_attachments "$@" ;;
fetch) fetch_attachment "$@" ;;
*) printf 'linear-attachments: unknown-action=%s\n' "$action" >&2; exit 1 ;;
esac
