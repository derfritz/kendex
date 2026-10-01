#!/bin/bash
# Linear GraphQL API - User Operations
# Usage: users.sh <action> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << 'EOF'
User Operations

Usage: users.sh <action> [options]

Actions:
  list    List users
  get     Get a single user by ID, name, or "me"
  me      Get current user (shorthand for "get me")

List Options:
  --limit <n>           Max results (default: 75; the API's largest page is 250)

Get:
  users.sh get <id-or-name>
  users.sh get me

Examples:
  users.sh list
  users.sh get me
  users.sh me
  users.sh get "Brad M"
EOF
}
case "${1:-help}" in help|--help|-h) show_help; exit 0 ;; esac

source "$SCRIPT_DIR/../lib/common.sh"

list_users() {
    local first=75
    local total_limit=75
    FORMAT="${DEFAULT_FORMAT}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max) total_limit=0; shift ;;
            --limit)
                first="$2"; total_limit="$2"
                shift 2
                ;;
            --format) FORMAT="$2"; shift 2 ;;
            --format=*) FORMAT="${1#--format=}"; shift ;;
            --) shift; break ;;
            -*) echo "{\"error\": \"Unknown option: $1. Run --help for valid options.\"}" >&2; return 1 ;;
            *) break ;;
        esac
    done

    local query='
    query ListUsers($first: Int, $after: String) {
        users(first: $first, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
                id
                name
                email
                displayName
                active
                admin
                createdAt
            }
        }
    }'

    linear_require_pattern --limit "$first" '^[0-9]+$' 'a non-negative integer' || return 1
    if (( first > 50 )); then first=50; fi
    local variables="{\"first\": $first}"
    local result
    result=$(graphql_pages "$query" "$variables" "users" "$total_limit")

    # Apply output format
    case "$FORMAT" in
        raw)
            linear_public_result "$result"
            ;;
        safe|*)
            format_users_list "$result"
            ;;
    esac
}

get_user() {
    local user_ref=""
    FORMAT="${DEFAULT_FORMAT}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) FORMAT="$2"; shift 2 ;;
            --format=*) FORMAT="${1#--format=}"; shift ;;
            *) user_ref="$1"; shift ;;
        esac
    done

    if [ -z "$user_ref" ]; then
        echo '{"error": "User ID or \"me\" required"}' >&2
        return 1
    fi

    local result
    if [ "$user_ref" = "me" ]; then
        local query='
        query GetViewer {
            viewer {
                id
                name
                email
                displayName
                active
                admin
                teams(first: 10) { pageInfo { hasNextPage endCursor } nodes { name } }
                createdAt
            }
        }'
        result=$(graphql_query "$query" "{}")
    else
        local query='
        query GetUser($id: String!) {
            user(id: $id) {
                id
                name
                email
                displayName
                active
                admin
                teams(first: 10) { pageInfo { hasNextPage endCursor } nodes { name } }
                createdAt
            }
        }'
        local variables="{\"id\": \"$user_ref\"}"
        result=$(graphql_query "$query" "$variables")
    fi

    # Apply output format
    case "$FORMAT" in
        raw)
            linear_public_result "$result"
            ;;
        safe|*)
            format_user_single "$result"
            ;;
    esac
}

# Main routing
action="${1:-help}"
shift || true

case "$action" in
    list)
        list_users "$@"
        ;;
    get)
        if [ -z "${1:-}" ]; then
            echo '{"error": "Usage: users.sh get <id-or-name|me>"}' >&2
            exit 1
        fi
        get_user "$@"
        ;;
    me)
        get_user "me" "${@}"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Error: Unknown action '$action'" >&2
        echo "Run 'users.sh --help' for usage." >&2
        exit 1
        ;;
esac
