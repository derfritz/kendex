#!/usr/bin/env bash
# Tests for scripts/lib/overseer-memory.sh, the reader and judge of the
# overseer's two memory marks, over a fake /proc and cgroup tree the library's
# ORCH_MEMORY_PROC_ROOT and ORCH_MEMORY_CGROUP_ROOT point it at. Five
# surfaces, each with one control that mutates a private copy of the library:
# the settings read, the figures read, the judgement, and the overlap check
# before and after a launch.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-env.sh"
# mutant_scripts and mutate_file, the two halves of each control.
# shellcheck source=lib/growth-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/growth-state.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$TEST_DIR/../scripts/lib/overseer-memory.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
PROC="$TMP_ROOT/proc"
CG="$TMP_ROOT/cgroup"

PASS=0
FAIL=0
check() { # NAME GOT WANT
  if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$1" "$3" "$2"; fi
}
assert_eq() { check "$3" "$1" "$2"; }

MIB=1048576

# fake_proc PID COMM KIB|none [CHILD...] — one process: its name, its VmRSS
# (none writes a status file without one, as a zombie's), and the children its
# one thread forked.
fake_proc() {
  local pid="$1" comm="$2" kib="$3"
  shift 3
  mkdir -p "$PROC/$pid/task/$pid"
  printf '%s\n' "$comm" > "$PROC/$pid/comm"
  {
    printf 'Name:\t%s\nPid:\t%s\n' "$comm" "$pid"
    [[ "$kib" == none ]] || printf 'VmRSS:\t %s kB\n' "$kib"
    printf 'Threads:\t1\n'
  } > "$PROC/$pid/status"
  printf '%s' "$*" > "$PROC/$pid/task/$pid/children"
}

# fake_cgroup PID LINE — the process's /proc/<pid>/cgroup.
fake_cgroup() { printf '%s\n' "$2" > "$PROC/$1/cgroup"; }

# fake_slice PATH ANON_BYTES|none CURRENT_BYTES MAX OOM_KILLS — the slice's
# memory files; none leaves anon out of memory.stat.
fake_slice() {
  local dir="$CG$1"
  mkdir -p "$dir"
  {
    printf 'file 4096\n'
    [[ "$2" == none ]] || printf 'anon %s\n' "$2"
    printf 'kernel 8192\n'
  } > "$dir/memory.stat"
  printf '%s\n' "$3" > "$dir/memory.current"
  printf '%s\n' "$4" > "$dir/memory.max"
  printf 'low 0\nhigh 0\nmax 12\noom 0\noom_kill %s\n' "$5" > "$dir/memory.events"
}

SLICE=/user.slice/user-1000.slice
SCOPE="0::$SLICE/user@1000.service/app.slice/tmux-spawn-1.scope"

# The control VM's shape: a pane shell running the npm codex wrapper, whose
# codex binary is the root, with a tool shell and its child below that. The
# wrapper is neither root nor child. Figures in KiB: 900 MiB for the root,
# 10 and 5 MiB for its descendants.
world_codex() { # ROOT_KIB ANON_BYTES
  rm -rf -- "${PROC:?}" "${CG:?}"
  fake_proc 100 bash 4096 101
  fake_proc 101 node 51200 102
  fake_proc 102 codex "$1" 103
  fake_proc 103 bash 10240 104
  fake_proc 104 cargo 5120
  fake_cgroup 100 "$SCOPE"
  fake_slice "$SLICE" "$2" $((2400 * MIB)) $((2621 * MIB)) 3
}

# memory LIB PANE HARNESS [ENV=VAL...] -- EXPR — EXPR evaluated after the
# library has read and judged pane PANE, in a subshell of its own.
memory() {
  local lib="$1" pane="$2" harness="$3"
  shift 3
  local -a envs=()
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done
  shift
  env ${envs[@]+"${envs[@]}"} ORCH_MEMORY_PROC_ROOT="$PROC" ORCH_MEMORY_CGROUP_ROOT="$CG" \
    bash -c 'set -euo pipefail; source "$1"; shift
      overseer_memory_marks; overseer_memory_read "$1" "$2"; overseer_memory_judge; shift 2
      eval "$1"' _ "$lib" "$pane" "$harness" "$1"
}
FIELDS='printf "%s\n" "${MEMORY_FIELDS[*]}"'
STATES='printf "%s %s fired=%s unknown=%s\n" "$MEMORY_ROOT_STATE" "$MEMORY_ANON_STATE" "${MEMORY_FIRED:-none}" "${MEMORY_UNKNOWN:-none}"'
MARKS=(ORCH_OVERSEER_ROOT_RSS_MIB=1300 ORCH_OVERSEER_SLICE_ANON_MIB=2100)

echo "=== overseer-memory ==="

# --- the figures ----------------------------------------------------------
world_codex $((900 * 1024)) $((1950 * MIB))
check "the codex binary under its node wrapper is the root; its descendants are counted apart, the wrapper in neither" \
  "$(memory "$LIB" 100 codex "${MARKS[@]}" -- "$FIELDS")" \
  "root-rss=900 root-rss-mark=1300 slice-anon=1950 slice-anon-mark=2100 slice-current=2400 slice-max=2621 children-rss=15 root-pid=102 slice=$SLICE"

# Every way a figure cannot be taken, one row each: the world above with one
# thing taken away, and the field that must then read unknown.
for row in \
  "rm -f $PROC/102/comm|root-rss=unknown:no-harness-process|a pane with no process named for its harness" \
  "fake_proc 102 codex none 103|root-rss=unknown:rss-unreadable|a root with no resident size" \
  "rm -f $PROC/102/task/102/children|children-rss=unknown:children-unlisted|a root whose children cannot be listed" \
  "fake_cgroup 100 '0::/system.slice/tmux.service'|slice-anon=unknown:no-user-slice|a pane outside any user slice" \
  "fake_cgroup 100 '1:name=systemd:$SLICE/session-1.scope'|slice-anon=unknown:no-cgroup2|a pane on cgroup v1 alone" \
  "rm -f $PROC/100/cgroup|slice-anon=unknown:cgroup-unreadable|a pane whose cgroup cannot be read" \
  "fake_slice $SLICE none 1 2 0|slice-anon=unknown:stat-unreadable|a memory.stat with no anon line" \
  "rm -f $CG$SLICE/memory.max|slice-max=unknown:max-unreadable|a slice with no memory.max"; do
  IFS='|' read -r row_setup row_want row_label <<<"$row"
  world_codex $((900 * 1024)) $((1950 * MIB))
  eval "$row_setup"
  got="$(memory "$LIB" 100 codex "${MARKS[@]}" -- "$FIELDS")"
  check "$row_label reads $row_want" "$(tr ' ' '\n' <<<"$got" | grep -xF -- "$row_want" || echo "$got")" "$row_want"
done

world_codex $((900 * 1024)) $((1950 * MIB))
printf 'max\n' > "$CG$SLICE/memory.max"
check "an uncapped slice reads its cap as none" \
  "$(memory "$LIB" 100 codex "${MARKS[@]}" -- 'printf "%s\n" "$MEMORY_SLICE_MAX"')" "none"
check "a pane pid tmux could not name leaves every figure unknown" \
  "$(memory "$LIB" "" codex "${MARKS[@]}" -- 'printf "%s %s %s\n" "$MEMORY_ROOT_RSS" "$MEMORY_ANON" "$MEMORY_CHILDREN"')" \
  "unknown:pane-pid unknown:pane-pid unknown:pane-pid"
check "a claude pane's root is the process named for claude" \
  "$(fake_proc 100 bash 4096 105; fake_proc 105 claude 409600
     memory "$LIB" 100 claude "${MARKS[@]}" -- 'printf "%s %s\n" "$MEMORY_ROOT_PID" "$MEMORY_ROOT_RSS"')" \
  "105 400"

# --- the judgement --------------------------------------------------------
# The owner's boundaries: root-rss fires AT its mark, slice-anon only ABOVE
# its own, and an unknown figure neither fires nor stops the other firing.
for row in \
  "$((1300 * 1024 - 1))|$((1950 * MIB))|below below fired=none unknown=none|root-rss a KiB under 1300 MiB" \
  "$((1300 * 1024))|$((1950 * MIB))|reached below fired=root-rss unknown=none|root-rss at 1300 MiB" \
  "$((900 * 1024))|$((2100 * MIB))|below below fired=none unknown=none|slice-anon at 2100 MiB" \
  "$((900 * 1024))|$((2101 * MIB))|below reached fired=slice-anon unknown=none|slice-anon above 2100 MiB" \
  "$((1400 * 1024))|$((2200 * MIB))|reached reached fired=root-rss unknown=none|both past their marks" \
  "unknown|$((2101 * MIB))|unknown reached fired=slice-anon unknown=root-rss|slice-anon above its mark beside an unknown root-rss" \
  "$((1300 * 1024))|unknown|reached unknown fired=root-rss unknown=slice-anon|root-rss at its mark beside an unknown slice-anon" \
  "unknown|unknown|unknown unknown fired=none unknown=root-rss|both figures unknown"; do
  IFS='|' read -r row_kib row_anon row_want row_label <<<"$row"
  world_codex "${row_kib/unknown/1}" "${row_anon/unknown/1}"
  [[ "$row_kib" != unknown ]] || rm -f -- "$PROC/102/comm"
  [[ "$row_anon" != unknown ]] || fake_cgroup 100 '0::/system.slice/tmux.service'
  check "$row_label: $row_want" "$(memory "$LIB" 100 codex "${MARKS[@]}" -- "$STATES")" "$row_want"
done

world_codex $((5000 * 1024)) $((2600 * MIB))
check "with no mark set nothing fires, whatever the figures" \
  "$(memory "$LIB" 100 codex -- "$STATES")" "off off fired=none unknown=none"
check "the fired figure and its mark are the metric's own" \
  "$(memory "$LIB" 100 codex ORCH_OVERSEER_SLICE_ANON_MIB=2100 -- 'printf "%s %s %s\n" "$MEMORY_FIRED" "$MEMORY_FIRED_VALUE" "$MEMORY_FIRED_MARK"')" \
  "slice-anon 2600 2100"

# --- the settings ---------------------------------------------------------
marks() { # LIB ROOT ANON — the settings read alone
  env ORCH_OVERSEER_ROOT_RSS_MIB="$2" ORCH_OVERSEER_SLICE_ANON_MIB="$3" bash -c \
    'source "$1"; if overseer_memory_marks; then echo "root=${MEMORY_ROOT_MARK:-off} anon=${MEMORY_ANON_MARK:-off}"; else echo "bad $MEMORY_MARK_BAD"; fi' _ "$1"
}
for row in \
  "1300|2100|root=1300 anon=2100" \
  "||root=off anon=off" \
  "1300||root=1300 anon=off" \
  "0||bad ORCH_OVERSEER_ROOT_RSS_MIB=0" \
  "01300||bad ORCH_OVERSEER_ROOT_RSS_MIB=01300" \
  "|2100M|bad ORCH_OVERSEER_SLICE_ANON_MIB=2100M" \
  "|1234567890|bad ORCH_OVERSEER_SLICE_ANON_MIB=1234567890"; do
  IFS='|' read -r row_root row_anon row_want <<<"$row"
  check "settings root='$row_root' anon='$row_anon' read as $row_want" "$(marks "$LIB" "$row_root" "$row_anon")" "$row_want"
done

# --- the overlap ----------------------------------------------------------
OPEN='if overseer_memory_overlap_open; then echo "open headroom=$MEMORY_HEADROOM oom=$MEMORY_OOM_BEFORE"; else echo "refused $MEMORY_OVERLAP_REASON"; fi'
for row in \
  "$((2200 * MIB))||open headroom=421 oom=3|anon under the cap" \
  "$((2621 * MIB))||refused no-headroom|anon at the cap" \
  "$((2200 * MIB))|printf 'max\n' > $CG$SLICE/memory.max|open headroom=none oom=3|an uncapped slice" \
  "$((2200 * MIB))|rm -f $CG$SLICE/memory.max|refused max-max-unreadable|a cap that cannot be read" \
  "$((2200 * MIB))|fake_cgroup 100 '0::/system.slice/tmux.service'|refused anon-no-user-slice|anon that cannot be read" \
  "$((2200 * MIB))|rm -f $CG$SLICE/memory.events|refused events-unreadable|an oom_kill count that cannot be read"; do
  IFS='|' read -r row_anon row_setup row_want row_label <<<"$row"
  world_codex $((1300 * 1024)) "$row_anon"
  [[ -z "$row_setup" ]] || eval "$row_setup"
  check "before a launch, $row_label: $row_want" "$(memory "$LIB" 100 codex "${MARKS[@]}" -- "$OPEN")" "$row_want"
done

# held: the count read before the launch against the count after it, which
# the row rewrites between the two reads.
HELD='overseer_memory_overlap_open; eval "$HELD_BETWEEN"; if overseer_memory_overlap_held; then echo held; else echo "broken $MEMORY_OVERLAP_REASON"; fi'
for row in \
  ":|held|no OOM kill during the overlap" \
  "printf 'oom_kill 4\\n' > $CG$SLICE/memory.events|broken oom-kill|an OOM kill during the overlap" \
  "rm -f $CG$SLICE/memory.events|broken events-unreadable|memory.events gone after the launch"; do
  IFS='|' read -r row_between row_want row_label <<<"$row"
  world_codex $((1300 * 1024)) $((2200 * MIB))
  check "after a launch, $row_label: $row_want" \
    "$(memory "$LIB" 100 codex "${MARKS[@]}" HELD_BETWEEN="$row_between" -- "$HELD")" "$row_want"
done

# --- controls ---------------------------------------------------------------
# One per surface, each on a private copy of the library beside links to its
# siblings, so the copy still sources lib/lane-context.sh.
control() { # NAME OLD NEW
  local dir
  dir="$(mutant_scripts "$1" lib/overseer-memory.sh)" || exit 1
  mutate_file "$dir/lib/overseer-memory.sh" "$2" "$3"
  MUTANT="$dir/lib/overseer-memory.sh"
}

control marksctl '[[ "$1" =~ ^[1-9][0-9]{0,8}$ ]]' '[[ "$1" =~ ^[0-9]{1,9}$ ]]'
check "control: a settings rule admitting 0 reads a mark of nothing" \
  "$(marks "$MUTANT" 0 "")" "root=0 anon=off"

control readctl '! memory_rss_kib "$pid" || total=$((total + MEMORY_KIB))' ':'
world_codex $((900 * 1024)) $((1950 * MIB))
check "control: a reader that drops the descendants' sizes reads children-rss as 0" \
  "$(memory "$MUTANT" 100 codex "${MARKS[@]}" -- 'printf "%s\n" "$MEMORY_CHILDREN"')" "0"

control judgectl 'at-or-above) (( $3 < $2 )) || state=reached ;;' 'at-or-above) (( $3 <= $2 )) || state=reached ;;'
world_codex $((1300 * 1024)) $((1950 * MIB))
check "control: a judgement firing only above the root mark leaves 1300 MiB below it" \
  "$(memory "$MUTANT" 100 codex "${MARKS[@]}" -- "$STATES")" "below below fired=none unknown=none"

control openctl 'if (( MEMORY_HEADROOM <= 0 )); then' 'if (( MEMORY_HEADROOM < 0 )); then'
world_codex $((1300 * 1024)) $((2621 * MIB))
check "control: an overlap check admitting no headroom opens at the cap" \
  "$(memory "$MUTANT" 100 codex "${MARKS[@]}" -- "$OPEN")" "open headroom=0 oom=3"

control heldctl 'if (( MEMORY_OOM_KILLS != MEMORY_OOM_BEFORE )); then' 'if (( 0 )); then'
world_codex $((1300 * 1024)) $((2200 * MIB))
check "control: an overlap check blind to the count holds through an OOM kill" \
  "$(memory "$MUTANT" 100 codex "${MARKS[@]}" \
     HELD_BETWEEN="printf 'oom_kill 4\\n' > $CG$SLICE/memory.events" -- "$HELD")" "held"

printf '\npass: %s   fail: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
