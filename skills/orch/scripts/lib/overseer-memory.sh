#!/usr/bin/env bash
# The overseer's memory, read and judged for oversee-succeed's two memory
# marks. Linux only: every figure comes from /proc and the cgroup v2 tree, and a
# host without them reads every figure unknown.
#
# Two figures are judged, and never added together:
#   root-rss    the resident size of the overseer's own harness process: the
#               shallowest process under the tmux pane whose name
#               lane_context_shape reads as the pane's harness. A codex CLI
#               installed through npm runs a node wrapper that spawns the codex
#               binary as its child; the binary is the root, and the wrapper is
#               neither the root nor one of its children.
#   slice-anon  `anon` in memory.stat of the systemd user slice, the
#               `user-<uid>.slice` on the pane process's own cgroup path:
#               the memory every process in that slice holds that page-cache
#               reclaim cannot drop. The slice's memory.current and memory.max
#               are reported beside it as context and never judged; current
#               counts page cache, which the kernel reclaims at the cap.
# children-rss is reported beside them and never judged: the resident size
# summed over the root's descendants. RSS counts a page shared between
# processes once in each, so the sum is a ceiling on what the children own.
#
# Each figure is a whole number of MiB, rounded down, or `unknown:<reason>`.
# An unknown figure is never a healthy one.
#
# The marks are operator settings with no package default; unset or empty is
# no mark, and each is compared in whole MiB, the unit every line shows:
#   ORCH_OVERSEER_ROOT_RSS_MIB    root-rss at or above it fires
#   ORCH_OVERSEER_SLICE_ANON_MIB  slice-anon above it fires
#
# Testing: ORCH_MEMORY_PROC_ROOT and ORCH_MEMORY_CGROUP_ROOT stand in for /proc
# and /sys/fs/cgroup.
#
# Sourced, never executed. Every MEMORY_* global is this library's answer,
# read by the script that sources it.
# shellcheck disable=SC2034

# shellcheck source=lane-context.sh
source "${BASH_SOURCE[0]%/*}/lane-context.sh"

MEMORY_ROOT_MARK="" MEMORY_ANON_MARK="" MEMORY_MARK_BAD=""
MEMORY_PROC="" MEMORY_CGROUP=""
MEMORY_ROOT_PID="" MEMORY_ROOT_RSS="" MEMORY_CHILDREN=""
MEMORY_SLICE="" MEMORY_SLICE_DIR="" MEMORY_ANON="" MEMORY_SLICE_CURRENT="" MEMORY_SLICE_MAX=""
MEMORY_ROOT_STATE="" MEMORY_ANON_STATE="" MEMORY_UNKNOWN="" MEMORY_UNKNOWN_REASON=""
MEMORY_FIRED="" MEMORY_FIRED_VALUE="" MEMORY_FIRED_MARK=""
MEMORY_FIELDS=()
MEMORY_HEADROOM="" MEMORY_OOM_BEFORE="" MEMORY_OOM_KILLS="" MEMORY_OVERLAP_REASON=""
MEMORY_KIB="" MEMORY_COMM=""

memory_number() { # VALUE — a whole number with no leading zero, 0 included
  local LC_ALL=C
  [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

memory_mark_valid() { # VALUE — a positive whole number of at most nine digits
  local LC_ALL=C
  [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]]
}

# overseer_memory_marks — the two settings into MEMORY_ROOT_MARK and
# MEMORY_ANON_MARK, each empty for no mark. Returns 1 with MEMORY_MARK_BAD set
# to NAME=VALUE for a value that is not a positive whole number: a leading zero
# is refused rather than read as octal by the comparison.
overseer_memory_marks() {
  local name value
  MEMORY_ROOT_MARK="" MEMORY_ANON_MARK="" MEMORY_MARK_BAD=""
  for name in ORCH_OVERSEER_ROOT_RSS_MIB ORCH_OVERSEER_SLICE_ANON_MIB; do
    value="${!name:-}"
    [[ -n "$value" ]] || continue
    if ! memory_mark_valid "$value"; then
      MEMORY_MARK_BAD="$name=$value"
      return 1
    fi
    case "$name" in
      ORCH_OVERSEER_ROOT_RSS_MIB) MEMORY_ROOT_MARK="$value" ;;
      ORCH_OVERSEER_SLICE_ANON_MIB) MEMORY_ANON_MARK="$value" ;;
    esac
  done
}

# Whether either memory mark is set: with neither, nothing is read at all.
overseer_memory_on() {
  [[ -n "$MEMORY_ROOT_MARK$MEMORY_ANON_MARK" ]]
}

# The pids PID's threads have forked, one per line. Returns 1 where no thread's
# children list could be read: a process that has exited, or a kernel built
# without CONFIG_PROC_CHILDREN.
memory_children() { # PID
  local f kids listed=1
  for f in "$MEMORY_PROC/$1"/task/*/children; do
    kids="$(cat -- "$f" 2>/dev/null)" || continue
    listed=0
    # Split on purpose: the file is one line of space-separated pids.
    # shellcheck disable=SC2086
    [[ -z "$kids" ]] || printf '%s\n' $kids
  done
  return "$listed"
}

# VmRSS of PID in KiB, into MEMORY_KIB. Returns 1 where the status file is gone
# or carries no VmRSS, as a zombie's and a kernel thread's carry none.
memory_rss_kib() { # PID
  local key value rest
  MEMORY_KIB=""
  { while read -r key value rest; do
      if [[ "$key" == VmRSS: ]]; then MEMORY_KIB="$value"; break; fi
    done < "$MEMORY_PROC/$1/status"; } 2>/dev/null || true
  memory_number "$MEMORY_KIB"
}

# The harness process under pane pid $1 whose name reads as harness $2, the
# shallowest first, into MEMORY_ROOT_PID. Returns 1 where none does.
memory_root() { # PANE_PID HARNESS
  local frontier="$1" next pid kids
  MEMORY_ROOT_PID=""
  while [[ -n "$frontier" ]]; do
    next=""
    for pid in $frontier; do
      MEMORY_COMM=""
      { IFS= read -r MEMORY_COMM < "$MEMORY_PROC/$pid/comm"; } 2>/dev/null || true
      if [[ -n "$MEMORY_COMM" && "$(lane_context_shape "$MEMORY_COMM")" == "$2" ]]; then
        MEMORY_ROOT_PID="$pid"
        return 0
      fi
      kids="$(memory_children "$pid")" || kids=""
      [[ -z "$kids" ]] || next+="$kids"$'\n'
    done
    frontier="$next"
  done
  return 1
}

# The resident size summed over ROOT's descendants, into MEMORY_CHILDREN. A
# descendant that exits mid-walk is absent, never a failure.
memory_children_rss() { # ROOT_PID
  local frontier next pid kids total=0
  if ! frontier="$(memory_children "$1")"; then
    MEMORY_CHILDREN=unknown:children-unlisted
    return 0
  fi
  while [[ -n "$frontier" ]]; do
    next=""
    for pid in $frontier; do
      ! memory_rss_kib "$pid" || total=$((total + MEMORY_KIB))
      kids="$(memory_children "$pid")" || kids=""
      [[ -z "$kids" ]] || next+="$kids"$'\n'
    done
    frontier="$next"
  done
  MEMORY_CHILDREN=$((total / 1024))
}

# One slice file's first line into the variable OUT: a whole number of MiB, or
# `none` for a cap of `max`. Returns 1, with OUT set to `unknown:<reason>`,
# where the file is unreadable or holds anything else.
memory_cgroup_mib() { # OUT FILE
  local line=""
  { IFS= read -r line < "$MEMORY_SLICE_DIR/$2"; } 2>/dev/null || true
  if [[ "$line" == max ]]; then
    printf -v "$1" none
  elif memory_number "$line"; then
    printf -v "$1" '%s' "$((line / 1048576))"
  else
    printf -v "$1" '%s' "unknown:${2#memory.}-unreadable"
    return 1
  fi
}

# The user slice PID runs in, and its anon, current and max figures.
memory_slice() { # PID
  local line="" path="" prefix="" seg key value anon="" segs=() LC_ALL=C
  MEMORY_SLICE="" MEMORY_SLICE_DIR=""
  if [[ ! -r "$MEMORY_PROC/$1/cgroup" ]]; then
    memory_slice_unknown cgroup-unreadable
    return 0
  fi
  { while IFS= read -r line; do
      case "$line" in 0::*) path="${line#0::}"; break ;; esac
    done < "$MEMORY_PROC/$1/cgroup"; } 2>/dev/null || true
  if [[ -z "$path" ]]; then
    memory_slice_unknown no-cgroup2
    return 0
  fi
  IFS=/ read -r -a segs <<<"${path#/}"
  for seg in ${segs[@]+"${segs[@]}"}; do
    prefix+="/$seg"
    if [[ "$seg" =~ ^user-[0-9]+\.slice$ ]]; then
      MEMORY_SLICE="$prefix"
      break
    fi
  done
  if [[ -z "$MEMORY_SLICE" ]]; then
    memory_slice_unknown no-user-slice
    return 0
  fi
  MEMORY_SLICE_DIR="$MEMORY_CGROUP$MEMORY_SLICE"
  { while read -r key value; do
      if [[ "$key" == anon ]]; then anon="$value"; break; fi
    done < "$MEMORY_SLICE_DIR/memory.stat"; } 2>/dev/null || true
  if memory_number "$anon"; then
    MEMORY_ANON=$((anon / 1048576))
  else
    MEMORY_ANON=unknown:stat-unreadable
  fi
  memory_cgroup_mib MEMORY_SLICE_CURRENT memory.current || true
  memory_cgroup_mib MEMORY_SLICE_MAX memory.max || true
}

memory_slice_unknown() { # REASON
  MEMORY_ANON="unknown:$1" MEMORY_SLICE_CURRENT="unknown:$1" MEMORY_SLICE_MAX="unknown:$1"
}

# overseer_memory_read PANE_PID HARNESS — every figure, for the pane whose
# process tmux reports as PANE_PID and whose harness the caller already named.
# Reads nothing it cannot and fails nothing: each figure it could not take is
# `unknown:<reason>`, so the judgement below meets every case.
overseer_memory_read() {
  MEMORY_PROC="${ORCH_MEMORY_PROC_ROOT:-/proc}"
  MEMORY_CGROUP="${ORCH_MEMORY_CGROUP_ROOT:-/sys/fs/cgroup}"
  MEMORY_ROOT_PID=""
  if [[ "$1" == 0 ]] || ! memory_number "$1"; then
    MEMORY_ROOT_RSS=unknown:pane-pid MEMORY_CHILDREN=unknown:pane-pid MEMORY_SLICE=""
    memory_slice_unknown pane-pid
    return 0
  fi
  if ! memory_root "$1" "$2"; then
    MEMORY_ROOT_RSS=unknown:no-harness-process MEMORY_CHILDREN=unknown:no-harness-process
  elif memory_rss_kib "$MEMORY_ROOT_PID"; then
    MEMORY_ROOT_RSS=$((MEMORY_KIB / 1024))
    memory_children_rss "$MEMORY_ROOT_PID"
  else
    MEMORY_ROOT_RSS=unknown:rss-unreadable
    memory_children_rss "$MEMORY_ROOT_PID"
  fi
  # The slice is the pane process's, not the root's: every process the pane
  # starts shares its user slice, so the one figure the root cannot be found
  # for is not taken with it.
  memory_slice "$1"
}

# One metric's state into OUT: off with no mark, unknown for an unknown
# figure, else reached or below by RULE.
memory_state() { # OUT MARK FIGURE RULE
  local state=below
  if [[ -z "$2" ]]; then
    state=off
  elif [[ "$3" == unknown:* ]]; then
    state=unknown
  else
    case "$4" in
      at-or-above) (( $3 < $2 )) || state=reached ;;
      above) (( $3 <= $2 )) || state=reached ;;
      *) printf 'overseer-memory: rule-unknown rule=%s\n' "$4" >&2; return 1 ;;
    esac
  fi
  printf -v "$1" '%s' "$state"
}

# overseer_memory_judge — the marks against the figures read. MEMORY_ROOT_STATE
# and MEMORY_ANON_STATE are each off, below, reached or unknown. MEMORY_FIRED
# names the metric that fired, root-rss ahead of slice-anon where both did, and
# is empty where neither did: an unknown figure never stops the other metric
# firing. MEMORY_FIRED_VALUE and MEMORY_FIRED_MARK are that metric's figure and
# mark. MEMORY_UNKNOWN names the first metric with a mark whose figure is
# unknown, and MEMORY_UNKNOWN_REASON that figure's reason, both empty where
# none is. MEMORY_FIELDS is every figure and mark as the key=value words a line
# carries.
overseer_memory_judge() {
  memory_state MEMORY_ROOT_STATE "$MEMORY_ROOT_MARK" "$MEMORY_ROOT_RSS" at-or-above
  memory_state MEMORY_ANON_STATE "$MEMORY_ANON_MARK" "$MEMORY_ANON" above
  MEMORY_FIRED="" MEMORY_FIRED_VALUE="" MEMORY_FIRED_MARK=""
  MEMORY_UNKNOWN="" MEMORY_UNKNOWN_REASON=""
  if [[ "$MEMORY_ROOT_STATE" == reached ]]; then
    MEMORY_FIRED=root-rss MEMORY_FIRED_VALUE="$MEMORY_ROOT_RSS" MEMORY_FIRED_MARK="$MEMORY_ROOT_MARK"
  elif [[ "$MEMORY_ANON_STATE" == reached ]]; then
    MEMORY_FIRED=slice-anon MEMORY_FIRED_VALUE="$MEMORY_ANON" MEMORY_FIRED_MARK="$MEMORY_ANON_MARK"
  fi
  if [[ "$MEMORY_ROOT_STATE" == unknown ]]; then
    MEMORY_UNKNOWN=root-rss MEMORY_UNKNOWN_REASON="${MEMORY_ROOT_RSS#unknown:}"
  elif [[ "$MEMORY_ANON_STATE" == unknown ]]; then
    MEMORY_UNKNOWN=slice-anon MEMORY_UNKNOWN_REASON="${MEMORY_ANON#unknown:}"
  fi
  MEMORY_FIELDS=(
    "root-rss=$MEMORY_ROOT_RSS" "root-rss-mark=${MEMORY_ROOT_MARK:-off}"
    "slice-anon=$MEMORY_ANON" "slice-anon-mark=${MEMORY_ANON_MARK:-off}"
    "slice-current=$MEMORY_SLICE_CURRENT" "slice-max=$MEMORY_SLICE_MAX"
    "children-rss=$MEMORY_CHILDREN" "root-pid=${MEMORY_ROOT_PID:-none}" "slice=${MEMORY_SLICE:-none}"
  )
}

# The slice's oom_kill count from memory.events, into MEMORY_OOM_KILLS.
memory_oom_kills() {
  local key value
  MEMORY_OOM_KILLS=""
  [[ -n "$MEMORY_SLICE_DIR" ]] || return 1
  { while read -r key value; do
      if [[ "$key" == oom_kill ]]; then MEMORY_OOM_KILLS="$value"; break; fi
    done < "$MEMORY_SLICE_DIR/memory.events"; } 2>/dev/null || true
  memory_number "$MEMORY_OOM_KILLS"
}

# overseer_memory_overlap_open — whether a successor may start beside this
# overseer under the slice cap, from the figures read. The predecessor runs
# until the successor shows a running turn, so both are in the slice at once.
# Safe needs slice-anon measured and below a measured cap (MEMORY_HEADROOM is
# the difference in MiB, or `none` for an uncapped slice) and the slice's
# oom_kill count read, which overseer_memory_overlap_held compares against once
# the successor runs. Returns 1 with MEMORY_OVERLAP_REASON naming what failed.
overseer_memory_overlap_open() {
  MEMORY_HEADROOM="" MEMORY_OOM_BEFORE="" MEMORY_OVERLAP_REASON=""
  if [[ "$MEMORY_ANON" == unknown:* ]]; then
    MEMORY_OVERLAP_REASON="anon-${MEMORY_ANON#unknown:}"
    return 1
  fi
  case "$MEMORY_SLICE_MAX" in
    unknown:*) MEMORY_OVERLAP_REASON="max-${MEMORY_SLICE_MAX#unknown:}"; return 1 ;;
    none) MEMORY_HEADROOM=none ;;
    *)
      MEMORY_HEADROOM=$((MEMORY_SLICE_MAX - MEMORY_ANON))
      if (( MEMORY_HEADROOM <= 0 )); then
        MEMORY_OVERLAP_REASON=no-headroom
        return 1
      fi
      ;;
  esac
  if ! memory_oom_kills; then
    MEMORY_OVERLAP_REASON=events-unreadable
    return 1
  fi
  MEMORY_OOM_BEFORE="$MEMORY_OOM_KILLS"
}

# overseer_memory_overlap_held — after the successor shows a running turn,
# whether the overlap held: no OOM kill in the slice since
# overseer_memory_overlap_open read the count. Returns 1 with
# MEMORY_OVERLAP_REASON set to events-unreadable or oom-kill.
overseer_memory_overlap_held() {
  MEMORY_OVERLAP_REASON=""
  if ! memory_oom_kills; then
    MEMORY_OVERLAP_REASON=events-unreadable
    return 1
  fi
  if (( MEMORY_OOM_KILLS != MEMORY_OOM_BEFORE )); then
    MEMORY_OVERLAP_REASON=oom-kill
    return 1
  fi
}
