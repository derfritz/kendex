# shellcheck shell=bash
#
# The Copilot CLI session record: the one adapter between the JSON the CLI
# hands its `statusLine` command on stdin and every reader that wants a live
# context, credit or permission figure for a Copilot session.
#
# Copilot keeps no live context count anywhere a reader can open: its
# `events.jsonl` transcript carries usage only in the `session.shutdown` event
# a session writes as it ends, and the pane footer is a display. The status
# line command is the one live producer. `copilot-statusline`, the script
# beside this library, is that command: it persists the exact JSON it received
# as a record bound to the session, and this library reads it back. Nothing
# here parses a pane or a screen.
#
# One record per session, at `<COPILOT_HOME>/lane-status/<session_id>.json`:
# the account directory the session runs under, so the record is bound to the
# launch identity by where it sits. The record carries the CLI's own fields
# under `status`, exactly as received, and beside them what binds it:
#
#   session_id       the CLI's, repeated at the top for a reader's match
#   transcript_path  the CLI's, so a hook payload naming a transcript is
#                    matched against the record and never against a guess
#   copilot_home     the account directory the session runs under
#   pid              the process the status line command was run by, for
#                    a reader holding a pane and asking which record is its
#   cwd              the directory the command ran in
#   written_at       epoch seconds, for the staleness rule below
#
# A reader answers with a record only where every binding it holds agrees:
# the session id it was handed, the transcript path where it has one, and a
# record no older than COPILOT_SESSION_MAX_AGE_S, an age equal to the bound
# still fresh. Anything else is unmeasured, under a reason the reader names,
# and never a figure: a record from another session, or one the CLI stopped
# refreshing, would read as a session with room for as long as it stood.
#
# Sourced, never run. Bash 3.2-safe, like its callers.

# The seam the shared token judge reads a Copilot lane's context through:
# copilot_session_context below. The lane turn-end hook calls it in place of
# its transcript read on a Copilot lane, and the fleet-wide judge that decides
# a handoff by tokens takes the same figure from the same call.
COPILOT_SESSION_MAX_AGE_S="${COPILOT_SESSION_MAX_AGE_S:-120}"

# The directory the records of the account at HOME live in.
copilot_session_dir() { # HOME
  printf '%s/lane-status\n' "$1"
}

# The record path for one session of the account at HOME. The id is held to
# the alphabet a session id is spelled in, so no id can name a path outside the
# directory; an id outside it answers 1.
copilot_session_record_path() { # HOME SESSION_ID
  case "$2" in
    '' | . | .. | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  printf '%s/%s.json\n' "$(copilot_session_dir "$1")" "$2"
}

# copilot_session_write HOME PID CWD < JSON — the record for the JSON on stdin,
# written whole under HOME. Prints nothing; 0 once the record stands. On any
# other answer COPILOT_SESSION_REASON names it:
#   payload=invalid-json   stdin is not a JSON object
#   payload=unbound        the object names no session_id, or one outside the
#                          alphabet a session id is spelled in
#   record=unwritable      the directory or the file could not be written
# The write is a temporary file renamed over the target, so a reader never
# meets half a record, and the directory is private: the record names the
# account's directory and the session's transcript.
COPILOT_SESSION_REASON=""
copilot_session_write() { # HOME PID CWD
  local home="$1" pid="$2" cwd="$3" input session path dir staged now
  COPILOT_SESSION_REASON=""
  input="$(cat)" || { COPILOT_SESSION_REASON=payload=invalid-json; return 1; }
  session="$(printf '%s' "$input" | jq -r 'if type == "object" then (.session_id // "") else error("not an object") end' 2>/dev/null)" \
    || { COPILOT_SESSION_REASON=payload=invalid-json; return 1; }
  path="$(copilot_session_record_path "$home" "$session")" \
    || { COPILOT_SESSION_REASON=payload=unbound; return 1; }
  dir="${path%/*}"
  now="$(date +%s)" || { COPILOT_SESSION_REASON=record=unwritable; return 1; }
  ( umask 077 && mkdir -p -- "$dir" ) || { COPILOT_SESSION_REASON=record=unwritable; return 1; }
  staged="$path.$$"
  if ! printf '%s' "$input" | ( umask 077 && jq -c --arg home "$home" --arg pid "$pid" --arg cwd "$cwd" --argjson now "$now" '
      {session_id: .session_id,
       transcript_path: (.transcript_path // null),
       copilot_home: $home,
       pid: ($pid | if . == "" then null else tonumber end),
       cwd: $cwd,
       written_at: $now,
       status: .}' > "$staged" ); then
    rm -f -- "$staged"
    COPILOT_SESSION_REASON=record=unwritable
    return 1
  fi
  mv -f -- "$staged" "$path" || { rm -f -- "$staged"; COPILOT_SESSION_REASON=record=unwritable; return 1; }
}

# copilot_session_read HOME SESSION_ID [TRANSCRIPT] [NOW] — the record bound
# to SESSION_ID under HOME, into COPILOT_SESSION_RECORD, 0 where every
# binding agrees. Into a variable and never onto stdout: a caller reading it
# through a command substitution would lose the reason below with the
# subshell. 1 with COPILOT_SESSION_REASON naming the first binding that did
# not agree:
#   missing           no record for that session under HOME
#   unreadable        a file there that is not a JSON object with the fields
#   wrong-session     the record's own session_id is another session's
#   wrong-transcript  TRANSCRIPT was given and the record names another
#   stale             written_at is older than COPILOT_SESSION_MAX_AGE_S,
#                     later than NOW, or not a readable number: a record the
#                     CLI stopped refreshing, and one stamped by a clock ahead
#                     of the reader's, are both records nothing vouches for
# NOW is the clock, for a caller with an injected one; the default reads it.
COPILOT_SESSION_RECORD=""
copilot_session_read() { # HOME SESSION_ID [TRANSCRIPT] [NOW]
  local home="$1" session="$2" transcript="${3:-}" now="${4:-}" path record fields
  local rec_session rec_transcript written age
  COPILOT_SESSION_REASON=""
  COPILOT_SESSION_RECORD=""
  path="$(copilot_session_record_path "$home" "$session")" \
    || { COPILOT_SESSION_REASON=missing; return 1; }
  [ -f "$path" ] || { COPILOT_SESSION_REASON=missing; return 1; }
  record="$(cat -- "$path" 2>/dev/null)" || { COPILOT_SESSION_REASON=unreadable; return 1; }
  fields="$(printf '%s' "$record" | jq -r '
    if type != "object" or (.session_id | type) != "string" then error("shape") else . end
    | [.session_id, (.transcript_path // ""), (.written_at | if type == "number" then tostring else "" end)]
    | join("\t")' 2>/dev/null)" || { COPILOT_SESSION_REASON=unreadable; return 1; }
  rec_session="${fields%%	*}"
  fields="${fields#*	}"
  rec_transcript="${fields%%	*}"
  written="${fields#*	}"
  [ "$rec_session" = "$session" ] || { COPILOT_SESSION_REASON=wrong-session; return 1; }
  if [ -n "$transcript" ] && [ "$rec_transcript" != "$transcript" ]; then
    COPILOT_SESSION_REASON=wrong-transcript
    return 1
  fi
  case "$written" in
    '' | *[!0-9]*) COPILOT_SESSION_REASON=stale; return 1 ;;
  esac
  [ -n "$now" ] || now="$(date +%s)"
  age=$((now - written))
  { [ "$age" -ge 0 ] && [ "$age" -le "$COPILOT_SESSION_MAX_AGE_S" ]; } || { COPILOT_SESSION_REASON=stale; return 1; }
  COPILOT_SESSION_RECORD="$record"
}

# copilot_session_fields RECORD — one record split into the figures a reader
# acts on, each empty where the CLI sent none or sent a value of another type:
#   CS_MODEL        status.model.id
#   CS_USED_PCT     status.context_window.used_percentage, rounded
#   CS_TOKENS       status.context_window.current_context_tokens, whole
#   CS_WINDOW       status.context_window.context_window_size, whole
#   CS_NANO_AIU     status.ai_used.total_nano_aiu, whole
#   CS_ALLOW_ALL    true, false, or empty where the record does not say
# Empty is what a consumer reads as unmeasured; no field is ever defaulted to
# a number here.
CS_MODEL="" CS_USED_PCT="" CS_TOKENS="" CS_WINDOW="" CS_NANO_AIU="" CS_ALLOW_ALL=""
copilot_session_fields() { # RECORD
  local line
  CS_MODEL="" CS_USED_PCT="" CS_TOKENS="" CS_WINDOW="" CS_NANO_AIU="" CS_ALLOW_ALL=""
  line="$(printf '%s' "$1" | jq -r '
    def whole: if type == "number" then (floor | tostring) else "" end;
    def str: if type == "string" then . else "" end;
    [ (.status.model.id | str),
      (.status.context_window.used_percentage | if type == "number" then (. + 0.5 | floor | tostring) else "" end),
      (.status.context_window.current_context_tokens | whole),
      (.status.context_window.context_window_size | whole),
      (.status.ai_used.total_nano_aiu | whole),
      (.status.allow_all_enabled | if type == "boolean" then tostring else "" end) ]
    | join("\t")' 2>/dev/null)" || return 1
  CS_MODEL="${line%%	*}"; line="${line#*	}"
  CS_USED_PCT="${line%%	*}"; line="${line#*	}"
  CS_TOKENS="${line%%	*}"; line="${line#*	}"
  CS_WINDOW="${line%%	*}"; line="${line#*	}"
  CS_NANO_AIU="${line%%	*}"; line="${line#*	}"
  CS_ALLOW_ALL="$line"
}

# copilot_session_context HOME SESSION_ID [TRANSCRIPT] — the seam: the context
# tokens the session's record holds, printed as a whole number, 0. 1 with
# COPILOT_SESSION_REASON where no record answers (copilot_session_read's
# reasons), or `no-figure` where the record stands and carries no token count.
# A judge deciding a handoff by tokens calls this and nothing else for a
# Copilot session, so the lane's turn-end hook and the fleet judge cannot read
# one session two ways.
copilot_session_context() { # HOME SESSION_ID [TRANSCRIPT]
  copilot_session_read "$1" "$2" "${3:-}" || return 1
  copilot_session_fields "$COPILOT_SESSION_RECORD" || { COPILOT_SESSION_REASON=unreadable; return 1; }
  [ -n "$CS_TOKENS" ] || { COPILOT_SESSION_REASON=no-figure; return 1; }
  printf '%s\n' "$CS_TOKENS"
}

# The stop cause a record establishes for a launch that carried the full
# permission flag: `allow-all-blocked-by-policy` where the CLI reports
# allow_all_enabled false. An enterprise policy can block the allow-all mode
# and refreshes each hour, so a session launched with `--allow-all` can lose
# it mid-run; every tool call then asks a pane nobody answers. That is a stop
# with its own cause, never a stall. Prints the cause, 0; prints nothing, 1,
# where the record says allow-all is on or does not say.
copilot_session_stop_cause() { # RECORD
  copilot_session_fields "$1" || return 1
  [ "$CS_ALLOW_ALL" = false ] || return 1
  printf 'allow-all-blocked-by-policy\n'
}

# copilot_session_for_pane HOME PANE_PID [NOW] — the record of the session
# running under the pane whose shell is PANE_PID: the one fresh record under
# HOME whose recorded pid is that pid or a descendant of it, into
# COPILOT_SESSION_RECORD. 1 where none is, with COPILOT_SESSION_REASON
# `missing` for no fresh record under the pane and `stale` where a record
# under it is too old to serve. The parent chain is read through `ps`, one
# process at a time, bounded by the chain's own length.
copilot_session_for_pane() { # HOME PANE_PID [NOW]
  local home="$1" pane="$2" now="${3:-}" dir path record pid hops parent seen_stale=0
  COPILOT_SESSION_REASON=missing
  COPILOT_SESSION_RECORD=""
  dir="$(copilot_session_dir "$home")"
  [ -d "$dir" ] || return 1
  [ -n "$now" ] || now="$(date +%s)"
  for path in "$dir"/*.json; do
    [ -f "$path" ] || continue
    record="$(cat -- "$path" 2>/dev/null)" || continue
    pid="$(printf '%s' "$record" | jq -r '.pid | if type == "number" then tostring else "" end' 2>/dev/null)" || continue
    [ -n "$pid" ] || continue
    hops=0
    while [ -n "$pid" ] && [ "$pid" != 0 ] && [ "$hops" -lt 64 ]; do
      if [ "$pid" = "$pane" ]; then
        if copilot_session_read "$home" "$(printf '%s' "$record" | jq -r '.session_id // ""')" "" "$now"; then
          return 0
        fi
        [ "$COPILOT_SESSION_REASON" != stale ] || seen_stale=1
        break
      fi
      parent="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" || parent=""
      pid="$parent"
      hops=$((hops + 1))
    done
  done
  COPILOT_SESSION_REASON=missing
  [ "$seen_stale" -eq 0 ] || COPILOT_SESSION_REASON=stale
  return 1
}
