#!/usr/bin/env bash
# Tests for oversee-succeed's two memory marks over a real tmux server on a
# private socket, with the caller pane's processes and its user slice read
# from a fake /proc and cgroup tree (lib/overseer-memory.sh's
# ORCH_MEMORY_PROC_ROOT and ORCH_MEMORY_CGROUP_ROOT) keyed to the pane's real
# pid. What the library reads and judges is overseer_memory.sh's subject; this
# suite asserts what the script does with the answer: the line --check-marks
# prints, the overlap refusal before a launch and after one, and the cause the
# handoff file carries. The account triggers stay switched off or with room,
# and the context under its mark, so memory is the only mark in play.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-env.sh"
# shellcheck source=lib/lanes-fixture.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/lanes-fixture.sh"
# mutant_scripts and mutate_file, the two halves of the control.
# shellcheck source=lib/growth-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/growth-state.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUCCEED="$TEST_DIR/../scripts/oversee-succeed"

TMP_ROOT="$(mktemp -d)"
SOCK="oversee-succeed-memory-$$"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf -- "${TMP_ROOT:?}"
}
trap cleanup EXIT
tm() { tmux -L "$SOCK" "$@"; }

PASS=0
FAIL=0
check() { # NAME GOT WANT
  if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: %s\n        got:      %s\n' "$1" "$3" "$2"; fi
}
assert_eq() { check "$3" "$1" "$2"; }

PROC="$TMP_ROOT/proc"
CG="$TMP_ROOT/cgroup"
SLICE=/user.slice/user-1000.slice
MIB=1048576

# The successor's harness: records that it ran, draws a running turn, and
# where $TMP_ROOT/oom-on-start exists writes the OOM kill the slice records
# while both overseers run.
BIN="$TMP_ROOT/bin"
mkdir -p "$BIN" "$TMP_ROOT/work/tmp/handoffs"
cat > "$BIN/claude" <<STUB
#!/bin/sh
printf 'started\n' > "$TMP_ROOT/argv.claude"
[ ! -f "$TMP_ROOT/oom-on-start" ] || printf 'oom 1\noom_kill 4\n' > "$CG$SLICE/memory.events"
echo 'esc to interrupt'
exec sleep 100000
STUB
chmod +x "$BIN/claude"

new_home fleet
make_lane "$H" claude
FETCHER="$TMP_ROOT/fetch"
make_fetcher "$FETCHER"
claude_usage 60 20 5 Opus > "$FIXTURE_DIR/.claude.json"

env PATH="$BIN:$PATH" tmux -L "$SOCK" -f /dev/null new-session -d -s fleet -x 220 -y 50 'exec sleep 100000'
tm set-option -g default-shell /bin/sh
tm set-option -g renumber-windows off
# The successor pane as a non-login shell under this fixture's PATH, so the
# stub is the claude it runs on any host (oversee_succeed.sh says why).
tm set-option -g default-command "PATH=$BIN:\$PATH; export PATH; exec /bin/sh"
TMUX_ADDR="$(tm display-message -p '#{socket_path},#{pid},0')"

UNDER_MARK='  kendex (ken-1453) Fable 5.1 (1M context) 10% (fixture@example.com)     /rc'

# new_caller — every window past index 0 closed, then a caller pane under
# both context marks, in the directory the handoff path resolves against; sets
# CALLER_PANE, CALLER_WINDOW and CALLER_PID.
new_caller() {
  local f="$TMP_ROOT/caller.screen" spec
  printf '%s\n' "$UNDER_MARK" > "$f"
  tm kill-window -a -t fleet:0
  spec="$(tm new-window -d -t fleet:1 -c "$TMP_ROOT/work" -P -F '#{pane_id} #{window_id} #{pane_pid}' \
    "cat '$f'; exec sleep 100000")"
  read -r CALLER_PANE CALLER_WINDOW CALLER_PID <<<"$spec"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ "$(tm capture-pane -p -t "$CALLER_PANE")" != *"(fixture@example.com)"* ]] || return 0
    sleep 0.2
  done
  echo "fixture: caller pane never drew its screen" >&2
  exit 1
}

# world ROOT_MIB|none ANON_MIB|none — the fake tree under the caller pane's
# real pid: the pane process, its claude root at ROOT_MIB (none names no
# process for the harness), a 12 MiB child, and a slice at ANON_MIB (none puts
# the pane outside any user slice) with a 2621 MiB cap and three OOM kills.
world() {
  local root="$1" anon="$2" comm=claude
  rm -rf -- "${PROC:?}" "${CG:?}" "$TMP_ROOT/oom-on-start"
  mkdir -p "$PROC/$CALLER_PID/task/$CALLER_PID" "$PROC/900001/task/900001" "$PROC/900002/task/900002"
  printf 'sleep\n' > "$PROC/$CALLER_PID/comm"
  printf 'VmRSS:\t 1024 kB\n' > "$PROC/$CALLER_PID/status"
  printf '900001' > "$PROC/$CALLER_PID/task/$CALLER_PID/children"
  [[ "$root" != none ]] || { comm=node; root=40; }
  printf '%s\n' "$comm" > "$PROC/900001/comm"
  printf 'VmRSS:\t %s kB\n' "$((root * 1024))" > "$PROC/900001/status"
  printf '900002' > "$PROC/900001/task/900001/children"
  printf 'bash\n' > "$PROC/900002/comm"
  printf 'VmRSS:\t %s kB\n' "$((12 * 1024))" > "$PROC/900002/status"
  if [[ "$anon" == none ]]; then
    printf '0::/system.slice/tmux.service\n' > "$PROC/$CALLER_PID/cgroup"
    return 0
  fi
  printf '0::%s/session-1.scope\n' "$SLICE" > "$PROC/$CALLER_PID/cgroup"
  mkdir -p "$CG$SLICE"
  printf 'anon %s\nfile 4096\n' "$((anon * MIB))" > "$CG$SLICE/memory.stat"
  printf '%s\n' "$((2400 * MIB))" > "$CG$SLICE/memory.current"
  printf '%s\n' "$((2621 * MIB))" > "$CG$SLICE/memory.max"
  printf 'oom 0\noom_kill 3\n' > "$CG$SLICE/memory.events"
}

# run_succeed ARGS... — the script under an explicit, whole environment with
# the operator's marks from ROOT_MARK and ANON_MARK; sets OUT (both streams)
# and RC.
run_succeed() {
  rm -f -- "$TMP_ROOT/argv.claude"
  RC=0
  OUT="$(cd "$TMP_ROOT/work" && env -i HOME="$H" PATH="$BIN:$PATH" TMUX="$TMUX_ADDR" TMUX_PANE="$CALLER_PANE" \
    LANES_HOME="$H" FIXTURE_DIR="$FIXTURE_DIR" OVERSEE_WATCH_STATE_DIR="$TMP_ROOT/state" \
    CLAUDE_CONFIG_DIR="$H/.claude" ORCH_LANES_FETCH_CMD="$FETCHER" ORCH_LANE_DIRS="$H/.claude" \
    ORCH_OVERSEER_WALL_MINUTES=0 ORCH_OVERSEER_SUCCESSOR_ACCOUNTS=0 \
    ORCH_OVERSEER_ROOT_RSS_MIB="${ROOT_MARK-1300}" ORCH_OVERSEER_SLICE_ANON_MIB="${ANON_MARK-2100}" \
    ORCH_MEMORY_PROC_ROOT="$PROC" ORCH_MEMORY_CGROUP_ROOT="$CG" \
    "${SUCCEED_BIN:-$SUCCEED}" "$@" 2>&1)" || RC=$?
}

caller_open() { if [[ "$(tm list-windows -t fleet -F '#{window_id}')" == *"$CALLER_WINDOW"* ]]; then echo yes; else echo no; fi; }
overseers() { tm list-windows -t fleet -F '#{window_name}' | awk '$0 == "overseer"' | wc -l | tr -d ' '; }
launched() { if [[ -f "$TMP_ROOT/argv.claude" ]]; then echo yes; else echo no; fi; }
keyed() { awk -v k="oversee-succeed: $1" 'index($0, k) == 1 { print; exit }' <<<"$2"; }
fields() { # ROOT ANON — the memory words every line below carries
  printf 'root-rss=%s root-rss-mark=1300 slice-anon=%s slice-anon-mark=2100 slice-current=%s slice-max=%s children-rss=%s root-pid=%s slice=%s' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}
HANDOFF="$TMP_ROOT/work/tmp/handoffs/OVERSEER-HANDOFF.md"

echo "=== oversee-succeed memory marks ==="

# --- the judgement ----------------------------------------------------------
# The owner's policy on the control VM: root-rss at or above 1300 MiB, or
# slice-anon above 2100 MiB. Each row is one reading, and the line is what the
# watch and the turn-end hook read. Both figures ride on every line.
for row in \
  "1300|1950|mark-reached kind=root-rss value=1300 mark=1300 succession=on $(fields 1300 1950 2400 2621 12 900001 "$SLICE")|root-rss at its mark" \
  "1299|2101|mark-reached kind=slice-anon value=2101 mark=2100 succession=on $(fields 1299 2101 2400 2621 12 900001 "$SLICE")|slice-anon above its mark, root-rss under its own" \
  "none|2101|mark-reached kind=slice-anon value=2101 mark=2100 succession=on $(fields unknown:no-harness-process 2101 2400 2621 unknown:no-harness-process none "$SLICE")|slice-anon above its mark beside an unknown root-rss" \
  "1300|none|mark-reached kind=root-rss value=1300 mark=1300 succession=on $(fields 1300 unknown:no-user-slice unknown:no-user-slice unknown:no-user-slice 12 900001 none)|root-rss at its mark beside an unknown slice-anon" \
  "none|none|mark-unmeasured kind=root-rss reason=root-rss-no-harness-process succession=on $(fields unknown:no-harness-process unknown:no-user-slice unknown:no-user-slice unknown:no-user-slice unknown:no-harness-process none none)|both figures unknown" \
  "1299|2100|context-below-mark tokens=100000 mark=500000 headroom=40 $(fields 1299 2100 2400 2621 12 900001 "$SLICE")|both under their marks, the loaded marks reported"; do
  IFS='|' read -r row_root row_anon row_want row_label <<<"$row"
  new_caller
  world "$row_root" "$row_anon"
  run_succeed --check-marks
  check "--check-marks, $row_label" "$RC|$(sed -n 1p <<<"$OUT")|$(overseers)" "0|oversee-succeed: $row_want|0"
done

new_caller
world 5000 2600
ROOT_MARK="" ANON_MARK="" run_succeed --check-marks
check "--check-marks with no memory mark set reads no memory at all" \
  "$RC|$(sed -n 1p <<<"$OUT")" "0|oversee-succeed: context-below-mark tokens=100000 mark=500000 headroom=40"

new_caller
ROOT_MARK=1300M run_succeed --check-marks
check "a mark in any other shape than whole MiB is refused" \
  "$RC|$(sed -n 1p <<<"$OUT")" "1|oversee-succeed: invalid-memory-mark ORCH_OVERSEER_ROOT_RSS_MIB=1300M"

# --- the launch -------------------------------------------------------------
# A memory mark keeps the caller's account, which has room; what the launch
# has to establish is room in the slice for two overseers at once.
new_caller
world 1300 none
: > "$HANDOFF"
run_succeed
check "a slice nothing measured launches no successor beside a reached root mark" \
  "$RC|$(sed -n 1p <<<"$OUT")|$(overseers)|$(caller_open)|$(launched)|$(wc -c < "$HANDOFF" | tr -d ' ')" \
  "1|oversee-succeed: memory-overlap-unsafe reason=anon-no-user-slice $(fields 1300 unknown:no-user-slice unknown:no-user-slice unknown:no-user-slice 12 900001 none)|0|yes|no|0"

new_caller
world 1300 2621
run_succeed
check "anonymous memory at the slice cap launches no successor" \
  "$RC|$(keyed memory-overlap-unsafe "$OUT" | cut -d' ' -f1-3)|$(overseers)|$(launched)" \
  "1|oversee-succeed: memory-overlap-unsafe reason=no-headroom|0|no"

new_caller
world 1300 1950
touch "$TMP_ROOT/oom-on-start"
: > "$HANDOFF"
run_succeed
check "an OOM kill in the slice while both run closes the successor and keeps the caller" \
  "$RC|$(keyed successor-memory-unsafe "$OUT" | sed 's/ window=@[0-9]*//')|$(overseers)|$(caller_open)|$(launched)" \
  "1|oversee-succeed: successor-memory-unsafe reason=oom-kill oom-kills-before=3 oom-kills=4|0|yes|yes"

new_caller
world 1300 1950
printf '# handoff\n' > "$HANDOFF"
run_succeed
check "room in the slice: the successor takes the caller's slot" \
  "$RC|$(keyed successor-working "$OUT" | cut -d' ' -f1-2)|$(overseers)|$(caller_open)" \
  "0|oversee-succeed: successor-working|1|no"
check "and the handoff file carries the mark as the succession's cause, both figures beside it" \
  "$(tail -n 1 "$HANDOFF")" \
  "Succession cause: oversee-succeed memory mark kind=root-rss value=1300 mark=1300 slice-headroom=671 $(fields 1300 1950 2400 2621 12 900001 "$SLICE")"

# --- control ------------------------------------------------------------------
# The one site that turns a fired memory metric into the mark. Without it the
# figures are read and printed and nothing fires.
CTL="$(mutant_scripts memoryctl oversee-succeed)" || exit 1
mutate_file "$CTL/oversee-succeed" '[[ -n "$MARK_KIND" || -z "$MEMORY_FIRED" ]] || MARK_KIND="$MEMORY_FIRED"' ':'
new_caller
world 1300 1950
SUCCEED_BIN="$CTL/oversee-succeed" run_succeed --check-marks
check "control: without that site a reached root mark reads below it" \
  "$RC|$(sed -n 1p <<<"$OUT" | cut -d' ' -f1-2)" "0|oversee-succeed: context-below-mark"

printf '\npass: %s   fail: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
