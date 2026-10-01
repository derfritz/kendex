#!/usr/bin/env bash
# Credential selection, renewal and mint responses without a local store.
set -euo pipefail
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/assert.sh"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
assert_tmpdir TMP_ROOT
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)"
PROJECT="$TMP_ROOT/project"
mkdir -p "$PROJECT/bin" "$PROJECT/.agents/skills"
git -C "$PROJECT" init -q -b main
git -C "$PROJECT" config gc.auto 0
git -C "$PROJECT" config maintenance.auto false
fixture_root=$(git -C "$PROJECT" rev-parse --show-toplevel)
assert_eq 'fixture Git root stays in scratch' "$fixture_root" "$PROJECT"
# Only fixture setup inherits Git redirects. Request children use env -i,
# so repeating their OAuth cases cannot test the caller's Git environment.
if [[ "${OAUTH_GIT_REDIRECT_CHILD:-0}" == 1 ]]; then
    exit 0
fi
cp -R -- "$SKILL_DIR" "$PROJECT/.agents/skills/linear"
LINEAR="$PROJECT/.agents/skills/linear/scripts/linear.sh"
REAL_JQ=$(command -v jq)
cat >"$PROJECT/bin/date" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${NOW:?}"
SH
cat >"$PROJECT/bin/jq" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >>"$LOG/jq-argv"
exec "${REAL_JQ:?}" "$@"
SH
cat >"$PROJECT/bin/op" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$LOG/op"
case "$*" in
'read op://selected/app/id') printf 'resolved/id' ;;
'read op://selected/app/secret') printf 'resolved&secret' ;;
'read op://selected/app/token') printf 'resolved-token' ;;
*) exit 1 ;;
esac
SH
cat >"$PROJECT/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >>"$LOG/curl-argv"
if [[ "$*" == *'-K -'* ]]; then
    config=$(cat)
    printf '%s\n' "$config" >>"$LOG/config"
    if [[ "$config" == *'https://api.linear.app/oauth/token'* ]]; then
        printf 'mint\n' >>"$LOG/mints"
        n=$(wc -l <"$LOG/mints")
        if [[ "${MODE:-}" == token-response ]]; then
            printf '%s___HTTP_CODE___200' "${TOKEN_RESPONSE:?}"
            exit
        fi
        if [[ "${MODE:-}" == token-transport ]]; then exit 7; fi
        if [[ "${MODE:-}" == token-failure || ( "${FAIL_RENEWAL:-0}" == 1 && "$n" -gt 1 ) || ( "${MODE:-}" == references &&
            "$config" != *'client_id=resolved%2Fid&client_secret=resolved%26secret'* ) ]]; then
            printf '{"error":"invalid_client"}___HTTP_CODE___400'
        else
            printf '{"access_token":"token-%s","token_type":"Bearer","expires_in":3600}___HTTP_CODE___200' "$n"
        fi
        exit
    fi
    if [[ "$config" == *'https://uploads.linear.app/'* ]]; then
        sed -n 's/^header = "\(Authorization: .*\)"$/\1/p' <<<"$config" >>"$LOG/download-auth"
        n=$(wc -l <"$LOG/download-auth")
        IFS=, read -r -a codes <<<"${DOWNLOAD_RESPONSES:-200}"
        code="${codes[n-1]:-200}"
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -o) printf 'file body\n' >"$2"; shift 2 ;;
            -D) printf 'Content-Type: text/plain\n' >"$2"; shift 2 ;;
            *) shift ;;
            esac
        done
        if [[ "$code" == 000 ]]; then exit 7; fi
        printf '%s' "$code"
        exit
    fi
    sed -n 's/^header = "Authorization: \(.*\)"$/\1/p' <<<"$config" >>"$LOG/auth"
    if [[ "${MODE:-}" == always-401 || ( "${MODE:-}" == once-401 && ! -f "$LOG/denied" ) ]]; then
        touch "$LOG/denied"
        printf '{}___HTTP_CODE___401'
    else
        printf '{"data":{"viewer":{"id":"actor-id","name":"Actor name"}}}___HTTP_CODE___200'
    fi
else
    echo 'fake-curl: transport=missing-stdin-config' >&2
    exit 1
fi
SH
cat >"$PROJECT/request" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$PWD/.agents/skills/linear/scripts/lib/common.sh"
graphql_query '{ viewer { id name } }' '{}'
SH
chmod +x "$PROJECT/bin/curl" "$PROJECT/bin/date" "$PROJECT/bin/jq" "$PROJECT/bin/op" "$PROJECT/request"
OUT="" RC=0 NOW=9000
LOG="$TMP_ROOT/log"
mkdir -p "$LOG"
# One app pair in the private file; an unresolved unused key must not block it.
printf 'LINEAR_CLIENT_ID="app/id"\nLINEAR_CLIENT_SECRET="app&secret"\nLINEAR_API_KEY="op://unused/key"\n' >"$PROJECT/.env.local"
run_oauth_request request
assert_eq 'mint: request succeeds' "$RC" 0
assert_not 'mint: no local store' test -e "$PROJECT/.cache/linear"
config=$(cat "$LOG/config")
assert_contains 'mint sends fixed scope and encoded client credentials' "$config" \
    'grant_type=client_credentials&scope=read%2Cwrite&client_id=app%2Fid&client_secret=app%26secret'
assert_not 'mint keeps client credentials out of jq arguments' \
    grep -F -e 'app&secret' -e 'app/id' "$LOG/jq-argv"
run_oauth_request request MODE=once-401
assert_eq '401 renewal succeeds' "$RC" 0
header=$(tail -n 1 "$LOG/auth")
assert_eq '401 renewal uses new token' "$header" 'Bearer token-3'
run_oauth_request request MODE=always-401
assert_ne 'a second 401 refuses' "$RC" 0
count=$(wc -l <"$LOG/mints")
assert_eq 'a second 401 never renews again' "${count//[[:space:]]/}" 5

# Each CLI process mints its own token. Rotation must reach that mint.
run_oauth_request request LINEAR_CLIENT_SECRET=rotated
assert_eq 'secret rotation succeeds' "$RC" 0
header=$(tail -n 1 "$LOG/auth")
assert_eq 'secret rotation mints a new token' "$header" 'Bearer token-6'
run_oauth_request request LINEAR_CLIENT_SECRET=bad MODE=token-failure
assert_ne 'token mint failure refuses instead of using personal key' "$RC" 0

# Reports retain key provenance without giving advice about an unused key.
for row in \
    'app-shadow|app/id|app&secret|op://unused/key|inherited-key||project-config|app|application|Bearer token-8' \
    'app-inherited|app/id|app&secret||inherited-key||environment|app|application|Bearer token-9' \
    'key-only|||personal-key|||project-config|api-key|user|personal-key' \
    'environment-app|env-app|env-secret|personal-key||override-key|override|app|application|Bearer token-10'; do
    IFS='|' read -r label id secret key inherited override key_source credential kind authorization <<<"$row"
    printf 'LINEAR_API_KEY="%s"\n' "$key" >"$PROJECT/.env.local"
    run_oauth_request auth-check LINEAR_CLIENT_ID="$id" LINEAR_CLIENT_SECRET="$secret" \
        LINEAR_API_KEY="$inherited" LINEAR_API_KEY_OVERRIDE="$override"
    assert_eq "$label: auth-check succeeds" "$RC" 0
    assert "$label: credential report" jq -e --arg source "$key_source" --arg credential "$credential" --arg kind "$kind" \
        '.ok and .credential == $credential and .actor == {kind:$kind,id:"actor-id",name:"Actor name"} and
         .api_key_source == $source and .team == null and .writes_enabled == false and
         (.warnings | length == 1 and all(.[]; contains("LINEAR_TEAM") and (contains("LINEAR_API_KEY") | not)))' <<<"$OUT"
    header=$(tail -n 1 "$LOG/auth")
    assert_eq "$label: selected authorization reaches GraphQL" "$header" "$authorization"
done

for row in 'no-credentials||||credential=unset' \
    'partial-app|partial|||credential=incomplete-app' \
    'partial-app-with-key|partial||personal-key|credential=incomplete-app' \
    'partial-secret-with-key||partial|personal-key|credential=incomplete-app'; do
    IFS='|' read -r label id secret key error <<<"$row"
    printf 'LINEAR_API_KEY="%s"\n' "$key" >"$PROJECT/.env.local"
    : >"$LOG/auth"
    run_oauth_request request LINEAR_CLIENT_ID="$id" LINEAR_CLIENT_SECRET="$secret" LINEAR_API_KEY_OVERRIDE="$key"
    assert_ne "$label: request refuses" "$RC" 0
    assert_file_contains "$label: selected credential refusal" "$LOG/error" "$error"
    assert_not "$label: no request reaches GraphQL" test -s "$LOG/auth"
done

# Only selected references resolve; no store is written.
printf 'LINEAR_CLIENT_ID="op://selected/app/id"\nLINEAR_CLIENT_SECRET="op://selected/app/secret"\nLINEAR_API_KEY="op://unused/key"\n' >"$PROJECT/.env.local"
: >"$LOG/op"
run_oauth_request request MODE=references
assert_eq 'live references: request succeeds' "$RC" 0
reads=$(sort -u "$LOG/op")
assert_eq 'live references: only selected app references resolve' "$reads" $'read op://selected/app/id\nread op://selected/app/secret'
assert_not 'live references: no local store' test -e "$PROJECT/.cache/linear"
printf 'LINEAR_API_KEY="personal-key"\n' >"$PROJECT/.env.local"
# A fleet's published token must not use the accompanying proxy-placeholder pair.
for row in \
    'token-only||||published-token|published-token' \
    'token-beats-pair|op://unused/id|op://unused/secret|personal-key|published-token|published-token' \
    'token-beats-partial|partial||personal-key|published-token|published-token' \
    'token-reference|op://unused/id|op://unused/secret|op://unused/key|op://selected/app/token|resolved-token'; do
    IFS='|' read -r label id secret key supplied token <<<"$row"
    rm -rf -- "$PROJECT/.cache/linear"
    printf 'LINEAR_APP_TOKEN="%s"\nLINEAR_API_KEY="%s"\n' "$supplied" "$key" >"$PROJECT/.env.local"
    : >"$LOG/mints"
    : >"$LOG/auth"
    : >"$LOG/op"
    run_oauth_request request LINEAR_CLIENT_ID="$id" LINEAR_CLIENT_SECRET="$secret"
    assert_eq "$label: request succeeds" "$RC" 0
    header=$(cat "$LOG/auth")
    assert_eq "$label: GraphQL Bearer header" "$header" "Bearer $token"
    assert_not "$label: never mints" test -s "$LOG/mints"
    assert_not "$label: cache directory absent" test -e "$PROJECT/.cache/linear"
    reads=$(cat "$LOG/op")
    if [[ "$label" == token-reference ]]; then
        assert_eq 'token-reference: only token resolves' "$reads" 'read op://selected/app/token'
    else
        assert_eq "$label: unused credentials never resolve" "$reads" ''
    fi
done

for row in 'token-check|auth-check||0' 'token-401|request|always-401|1'; do
    IFS='|' read -r label command mode expected_rc <<<"$row"
    : >"$LOG/auth"
    : >"$LOG/mints"
    run_oauth_request "$command" MODE="$mode" LINEAR_APP_TOKEN=environment-token \
        LINEAR_CLIENT_ID=app/id LINEAR_CLIENT_SECRET='app&secret' LINEAR_API_KEY_OVERRIDE=personal-key
    assert_eq "$label: request result" "$RC" "$expected_rc"
    header=$(cat "$LOG/auth")
    assert_eq "$label: one request uses environment token" "$header" 'Bearer environment-token'
    assert_not "$label: never mints" test -s "$LOG/mints"
    assert_not "$label: cache directory absent" test -e "$PROJECT/.cache/linear"
    if [[ "$command" == auth-check ]]; then
        assert_jq 'token-check: application actor' "$OUT" \
            '.ok and .credential == "app-token" and .actor == {kind:"application",id:"actor-id",name:"Actor name"}'
    else
        assert_file_contains 'token-401: credential diagnostic' "$LOG/error" 'linear-auth: http=401 credential=app-token'
        assert 'token-401: token replacement guidance' jq -e \
            '.error | test("expir|revok"; "i") and test("replac[^\n]*LINEAR_APP_TOKEN"; "i")' "$LOG/error"
    fi
done

# The mint host uses only its pair, even when a published token cannot resolve.
for row in 'mint-host|app/id|app&secret' 'mint-host-reference|op://selected/app/id|op://selected/app/secret'; do
    IFS='|' read -r label id secret <<<"$row"
    rm -rf -- "$PROJECT/.cache/linear"
    : >"$LOG/mints"
    : >"$LOG/auth"
    : >"$LOG/op"
    : >"$LOG/config"
    before=$(find "$PROJECT" -type f | sort)
    run_oauth_request auth-mint LINEAR_CLIENT_ID="$id" LINEAR_CLIENT_SECRET="$secret" \
        LINEAR_APP_TOKEN=op://unused/token LINEAR_API_KEY_OVERRIDE=op://unused/key
    assert_eq "$label: mint succeeds" "$RC" 0
    assert_jq "$label: token JSON" "$OUT" '. == {access_token:"token-1",expires_at:12600}'
    count=$(wc -l <"$LOG/mints")
    assert_eq "$label: one mint" "${count//[[:space:]]/}" 1
    assert_not "$label: no GraphQL call" test -s "$LOG/auth"
    assert_not "$label: cache directory absent" test -e "$PROJECT/.cache/linear"
    after=$(find "$PROJECT" -type f | sort)
    assert_eq "$label: no files added" "$after" "$before"
    if [[ "$label" == mint-host-reference ]]; then
        reads=$(cat "$LOG/op")
        assert_eq 'mint-host-reference: only pair resolves' "$reads" \
            $'read op://selected/app/id\nread op://selected/app/secret'
        config=$(cat "$LOG/config")
        assert_contains 'mint-host-reference: resolved pair reaches mint' "$config" \
            'client_id=resolved%2Fid&client_secret=resolved%26secret'
    fi
done

for row in 'mint-missing||' 'mint-missing-secret|app/id|' 'mint-missing-id||app&secret'; do
    IFS='|' read -r label id secret <<<"$row"
    : >"$LOG/mints"
    run_oauth_request auth-mint LINEAR_CLIENT_ID="$id" LINEAR_CLIENT_SECRET="$secret" \
        LINEAR_APP_TOKEN=published-token LINEAR_API_KEY_OVERRIDE=personal-key
    assert_eq "$label: refuses" "$RC" 1
    assert_file_contains "$label: incomplete pair diagnostic" "$LOG/error" 'credential=incomplete-app'
    assert_not "$label: never mints" test -s "$LOG/mints"
    assert_eq "$label: no stdout" "$OUT" ''
done

# Linear's token endpoint supplies token_type, access_token and expires_in.
for row in \
    'type|{"access_token":"token","token_type":"Basic","expires_in":3600}' \
    'empty|{"access_token":"","token_type":"Bearer","expires_in":3600}' \
    'expiry-low|{"access_token":"token","token_type":"Bearer","expires_in":60}' \
    'expiry-high|{"access_token":"token","token_type":"Bearer","expires_in":2592001}' \
    'expiry-fraction|{"access_token":"token","token_type":"Bearer","expires_in":3600.5}'; do
    IFS='|' read -r label response <<<"$row"
    run_oauth_request auth-mint LINEAR_CLIENT_ID=app/id LINEAR_CLIENT_SECRET='app&secret' \
        MODE=token-response TOKEN_RESPONSE="$response"
    assert_eq "mint-response-$label: refuses" "$RC" 1
    assert_file_contains "mint-response-$label: response diagnostic" "$LOG/error" 'token=invalid-response'
    assert_eq "mint-response-$label: no stdout" "$OUT" ''
done
for row in 'token-failure|token-http=400' 'token-transport|token=transport-failed'; do
    IFS='|' read -r mode diagnostic <<<"$row"
    run_oauth_request auth-mint LINEAR_CLIENT_ID=app/id LINEAR_CLIENT_SECRET='app&secret' MODE="$mode"
    assert_eq "mint-$mode: refuses" "$RC" 1
    assert_file_contains "mint-$mode: diagnostic" "$LOG/error" "$diagnostic"
    assert_eq "mint-$mode: no stdout" "$OUT" ''
done

run_oauth_git_redirects "$SCRIPT_DIR/oauth-auth.test.sh" "$TMP_ROOT/git-callers"
