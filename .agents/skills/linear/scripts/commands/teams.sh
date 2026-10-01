#!/bin/bash
# Linear GraphQL API - Team Operations
# Usage: teams.sh <action> [options]
# `keys` prints {urlKey: string, keys: string[]} for Slack's outbound linker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << 'EOF'
Team Operations

Usage: teams.sh <action> [options]

Actions:
  list    List teams
  get     Get a single team by ID or name
  keys    Read the workspace URL key and all team keys

List Options:
  --limit <n>           Max results (default: 50)

Get:
  teams.sh get <id-or-name>

Examples:
  teams.sh list
  teams.sh get "<team-name>"
EOF
}
case "${1:-help}" in help|--help|-h) show_help; exit 0 ;; esac

source "$SCRIPT_DIR/../lib/common.sh"

list_teams() {
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
    query ListTeams($first: Int, $after: String) {
        teams(first: $first, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
                id
                name
                key
                description
                members(first: 10) { pageInfo { hasNextPage endCursor } nodes { name email } }
                createdAt
            }
        }
    }'

    linear_require_pattern --limit "$first" '^[0-9]+$' 'a non-negative integer' || return 1
    if (( first > 50 )); then first=50; fi
    local variables="{\"first\": $first}"
    local result
    result=$(graphql_pages "$query" "$variables" "teams" "$total_limit")

    # Apply output format
    case "$FORMAT" in
        raw)
            linear_public_result "$result"
            ;;
        safe|*)
            format_teams_list "$result"
            ;;
    esac
}

team_keys() {
    local result
    result=$(graphql_query 'query TeamKeys { organization { urlKey teams(first: 10) { pageInfo { hasNextPage endCursor } nodes { key } } } }' '{}') || return $?
    jq -e '{urlKey: .organization.urlKey, keys: [.organization.teams.nodes[].key]}' <<<"$result"
}

get_team() {
    local team_ref=""
    FORMAT="${DEFAULT_FORMAT}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) FORMAT="$2"; shift 2 ;;
            --format=*) FORMAT="${1#--format=}"; shift ;;
            *) team_ref="$1"; shift ;;
        esac
    done

    if [ -z "$team_ref" ]; then
        echo '{"error": "Team ID or name required"}' >&2
        return 1
    fi

    # Check if it's a UUID or a name - resolve name to ID if needed
    local team_id="$team_ref"
    if ! [[ "$team_ref" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        # Look up by name
        local lookup_query='query GetTeamByName($name: String!, $after: String) { teams(filter: {name: {eq: $name}}, after: $after) { pageInfo { hasNextPage endCursor } nodes { id } } }'
        local lookup_result
        lookup_result=$(graphql_pages "$lookup_query" "{\"name\": \"$team_ref\"}" teams)
        team_id=$(echo "$lookup_result" | jq -r '.teams.nodes[0].id // empty')
        if [ -z "$team_id" ]; then
            echo "{\"error\": \"Team not found: $team_ref\"}" >&2
            return 1
        fi
    fi

    local query='
    query GetTeam($id: String!) {
        team(id: $id) {
            id
            name
            key
            description
            members(first: 10) { pageInfo { hasNextPage endCursor } nodes { name email } }
            labels(first: 10) { pageInfo { hasNextPage endCursor } nodes { name color } }
            states(first: 10) { pageInfo { hasNextPage endCursor } nodes { name type position } }
            createdAt
            updatedAt
        }
    }'

    local variables="{\"id\": \"$team_id\"}"
    local result
    result=$(graphql_query "$query" "$variables")

    # Apply output format
    case "$FORMAT" in
        raw)
            linear_public_result "$result"
            ;;
        safe|*)
            format_team_single "$result"
            ;;
    esac
}

# Main routing
action="${1:-help}"
shift || true

case "$action" in
    keys)
        team_keys "$@"
        ;;
    list)
        list_teams "$@"
        ;;
    get)
        if [ -z "${1:-}" ]; then
            echo '{"error": "Usage: teams.sh get <id-or-name>"}' >&2
            exit 1
        fi
        get_team "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Error: Unknown action '$action'" >&2
        echo "Run 'teams.sh --help' for usage." >&2
        exit 1
        ;;
esac
