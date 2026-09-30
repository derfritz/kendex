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
