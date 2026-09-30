# shellcheck shell=bash
# Shared by the watch's triage and owed reads. A complete team list answers
# both, including active items older than the triage floor. The snapshot is
# separate from the normalized Linear cache because live lists are not syncs.
watch_tracker_list() (
  local now file stamp out tmp errf="$WORK_DIR/tracker.err" rc=0
  now="$(date -u +%s)" || die time-failed "" "clock=UTC"
  file="$PROJECT_ROOT/.cache/linear/watch-team.json"
  if [[ -f "$file" ]]; then
    stamp="$(jq -er --arg team "$LINEAR_TEAM" '
      if (.team | type) != "string" or (.read_at | type) != "number" or (.issues | type) != "array"
      then error("tracker-cache-invalid")
      elif .team != $team then 0 else .read_at end' "$file" 2>"$errf")" \
      || die tracker-list-invalid "$(cat "$errf")" "path=$file"
    if (( now >= stamp && now - stamp < TRACKER_INTERVAL )); then
      jq -c '.issues' "$file" || die tracker-list-invalid "" "path=$file"
      return 0
    fi
  fi
  out="$(env LINEAR_USAGE_CALLER=overseer "$TRACKER" issues list --team "$LINEAR_TEAM" --max --require-complete --format=safe 2>"$errf")" || rc=$?
  [[ "$rc" -eq 0 ]] || die tracker-list-failed "$(cat "$errf")" "team=$LINEAR_TEAM" "exit=$rc"
  [[ ! -s "$errf" ]] || cat -- "$errf" >&2
  jq -e 'if type != "array" then error("tracker-type expected=array actual=\(type)") else true end' <<<"$out" >/dev/null 2>"$errf" \
    || die tracker-list-invalid "$(cat "$errf")" "team=$LINEAR_TEAM"
  mkdir -p -- "${file%/*}" || die tracker-list-failed "" "path=$file"
  tmp="$(mktemp "${file}.XXXXXX")" || die tracker-list-failed "" "path=$file"
  trap 'rm -f -- "$tmp"' EXIT
  jq -c --arg team "$LINEAR_TEAM" --argjson now "$now" \
    '{team: $team, read_at: $now, issues: .}' <<<"$out" >"$tmp" \
    || die tracker-list-invalid "" "path=$file"
  mv -- "$tmp" "$file" || die tracker-list-failed "" "path=$file"
  printf '%s\n' "$out"
)
