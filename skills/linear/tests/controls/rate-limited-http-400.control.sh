# Stop reclassifying a RATELIMITED body served with HTTP 400. The response then
# routes to the generic HTTP-error path, so callers are told the request was
# malformed rather than that they are being throttled.
control_expect "rate-limited 400 reports the rate limit"
control_replace scripts/lib/common.sh 1 \
    '            http_code=429' \
    '            :'

# Drop the reset that lanes need to schedule held tracker writes.
control_expect "quota 400 carries reset 1790749380000 beside the error"
control_replace scripts/lib/common.sh 1 \
    "                '{error: \"Rate limited. Try again later.\", \"Requests-Reset\": (if \$reset == \"\" then null else \$reset end)}' >&2" \
    "                '{error: \"Rate limited. Try again later.\"}' >&2"

# A reset header must not replace the error the cache-continuation caller reads.
control_expect "quota 429 carries reset 1790750580000 beside the error"
control_replace scripts/lib/common.sh 1 \
    "                '{error: \"Rate limited. Try again later.\", \"Requests-Reset\": (if \$reset == \"\" then null else \$reset end)}' >&2" \
    "                '{error: \"Rate limited. Try again later.\", \"Requests-Reset\": (if \$reset == \"\" then null else \$reset end)} | if \$reset == \"\" then . else del(.error) end' >&2"

# jq reads an absent key as null; the contract requires the key itself.
control_expect "quota 429 carries reset null beside the error"
control_replace scripts/lib/common.sh 1 \
    "                '{error: \"Rate limited. Try again later.\", \"Requests-Reset\": (if \$reset == \"\" then null else \$reset end)}' >&2" \
    "                '{error: \"Rate limited. Try again later.\", \"Requests-Reset\": (if \$reset == \"\" then null else \$reset end)} | if \$reset == \"\" then del(.\"Requests-Reset\") else . end' >&2"
