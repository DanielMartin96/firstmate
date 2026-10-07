#!/usr/bin/env bash
# host-handover-loop.sh <repo-root> <label>
#
# Drives the loop the captain reported on 2026-10-07 through the real
# supervision host, watcher, arm and drain binaries against a disposable home:
#   1. downtime with nothing queued (a watcher stopped by TERM, as a session exit leaves it)
#   2. the host's first park announces `check: rearm-resurface` once and leaves a successor for main
#   3. main's handling turn drains, finds nothing queued, ends WITHOUT acknowledging
#   4. the Stop that ended the turn parks the host again, which takes the successor's cycle over
#   -> before the fix the fresh cycle re-announces `check: rearm-resurface` within ~10s (the loop)
#   -> after the fix the host stays parked and quiet, and a real event still surfaces.
set -u
REPO=$(cd "$1" && pwd -P)
LABEL=$2
EV=/Users/daniel.martin/.no-mistakes/evidence/01M4B1K0FGC8S1VTZ8HQK1MZYM
OUT="$EV/host-loop-$LABEL"
rm -rf "$OUT"; mkdir -p "$OUT"
. "$REPO/tests/wake-helpers.sh"
[ "$ROOT" = "$REPO" ] || { echo "ROOT mismatch: $ROOT vs $REPO"; exit 2; }

HOST="$ROOT/bin/fm-supervision-host.sh"
WATCH_ARM="$ROOT/bin/fm-watch-arm.sh"
DRAIN="$ROOT/bin/fm-wake-drain.sh"
TMP_ROOT=$(fm_test_tmproot fm-host-handover)
FAKEBIN=$(fm_fakebin "$TMP_ROOT/fakebin")
ln -s /bin/bash "$FAKEBIN/claude"
FAKE_CLAUDE="$FAKEBIN/claude"
STUB="$TMP_ROOT/engine-stub"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
n=$(( $(ls "$FM_HOME"/engine-call.* 2>/dev/null | wc -l) + 1 ))
printf '%s\n' "$*" > "$FM_HOME/engine-call.$n"
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01,"usage":{"input_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1},"session_id":"stub"}\n'
SH
chmod +x "$STUB"
export FM_REPO="$ROOT"
export FM_SUPERVISION_ENGINE_CLAUDE_BIN="$STUB"
export FM_SUPERVISION_HOST_PRIMARY=claude
export FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999
export FM_SUPERVISION_ENGINE_GRACE=1
export FM_ARM_CONFIRM_TIMEOUT=30
unset FM_SUPERVISION_ACTOR FM_BRANCH_REPORT_TURN FM_LEASE_HOLDER_PID PI_CODING_AGENT

MIRROR_ROOT="$TMP_ROOT/mirror-root"
mkdir -p "$MIRROR_ROOT"; git init -q "$MIRROR_ROOT"; : > "$MIRROR_ROOT/AGENTS.md"; ln -s "$ROOT/bin" "$MIRROR_ROOT/bin"

home="$TMP_ROOT/home"
mkdir -p "$home/state" "$home/config" "$home/fakebin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$home/fakebin/tmux"; chmod +x "$home/fakebin/tmux"
make_fake_crew_state "$home/fakebin" >/dev/null
: > "$home/config/supervision-host"
printf 'project=demo\nwindow=fm-demo\nharness=claude\n' > "$home/state/demo.meta"
printf '{"hook_event_name":"UserPromptSubmit","prompt_id":"p0","prompt":"watch the fleet for me"}' > "$home/mirror-seed.0"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$OUT/transcript.txt"; }
marker() { cat "$home/state/.watcher-down" 2>/dev/null || echo '<absent>'; }
queue_rows() { [ -s "$home/state/.wake-queue" ] && wc -l < "$home/state/.wake-queue" | tr -d ' ' || echo 0; }
watcher_live() { local p; p=$(cat "$home/state/.watch.lock/pid" 2>/dev/null) || return 1; [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
host_exited() { [ -s "$home/host.rc" ]; }
wait_until() { local n=$1 i=0; shift; while [ "$i" -lt "$n" ]; do "$@" && return 0; sleep 0.1; i=$((i+1)); done; return 1; }
resurface_count() { grep -c 'check: rearm-resurface' "$home/state/.watch-deliveries.log" 2>/dev/null || echo 0; }

start_host() {  # [park options...]
  FM_HOME="$home" FM_CREW_STATE_BIN="$home/fakebin/fm-crew-state.sh" PATH="$home/fakebin:$PATH" \
    MIRROR_ROOT="$MIRROR_ROOT" "$FAKE_CLAUDE" -c '
      printf "%s\n" "$$" > "$FM_HOME/state/.lock"
      printf "%s\n" "$$" >> "$FM_HOME/claude-pids"
      rm -f "$FM_HOME/host.rc"
      for seed in "$FM_HOME"/mirror-seed.*; do
        [ -f "$seed" ] || continue
        FM_ROOT_OVERRIDE="$MIRROR_ROOT" "$MIRROR_ROOT/bin/fm-host-mirror.sh" hook claude < "$seed"
      done
      "$0" park "$@" > "$FM_HOME/host.out" 2>&1
      printf "%s\n" "$?" > "$FM_HOME/host.rc"
    ' "$HOST" "$@" 2>> "$home/claude.err" &
}

stop_home() {
  local pid arms='' i=0
  if [ -f "$home/state/.supervision-host" ]; then
    arms=$(awk -F '\t' '$1 == "arm" { print $2 }' "$home/state/.supervision-host")
    pid=$(awk -F '\t' '$1 == "host" { print $2; exit }' "$home/state/.supervision-host")
    [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true
    while [ "$i" -lt 50 ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; do sleep 0.1; i=$((i+1)); done
  fi
  for pid in $arms; do kill -TERM "$pid" 2>/dev/null || true; done
  pid=$(cat "$home/state/.watch.lock/pid" 2>/dev/null || true)
  [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true
  while IFS= read -r pid; do kill -TERM "$pid" 2>/dev/null || true; done < <(cat "$home/claude-pids" 2>/dev/null)
  sleep 1
}
trap 'stop_home; cp "$home/state/.supervision-host.log" "$OUT/supervision-host.log" 2>/dev/null; cp "$home/state/.watch-deliveries.log" "$OUT/watch-deliveries.log" 2>/dev/null; cp "$home/state/.watch-cycle-exits.log" "$OUT/watch-cycle-exits.log" 2>/dev/null; fm_test_cleanup' EXIT

log "=== $LABEL: repo=$REPO ==="

# 1. Downtime with nothing queued: a watcher stopped by TERM publishes it through its own close.
PATH="$home/fakebin:$PATH" FM_HOME="$home" "$WATCH_ARM" --restart > "$OUT/seed-arm.out" 2>&1 &
seed_arm=$!
wait_until 300 grep -q '^watcher: started ' "$OUT/seed-arm.out" || { log "FAIL: seed arm never started: $(cat "$OUT/seed-arm.out")"; exit 1; }
w=$(cat "$home/state/.watch.lock/pid"); kill -TERM "$w"
wait "$seed_arm" 2>/dev/null || true
log "step1 after watcher TERM: marker=$(marker) queue_rows=$(queue_rows)"
case "$(marker)" in pending:downtime:*) ;; *) log "FAIL: no downtime published"; exit 1 ;; esac

# 2. The host's first park: recovers the downtime once, passes it to main, leaves a successor.
start_host
wait_until 300 host_exited || { log "FAIL: host#1 never exited: $(cat "$home/state/.supervision-host.log")"; exit 1; }
log "step2 host#1 rc=$(cat "$home/host.rc") host.out: $(tr '\n' '|' < "$home/host.out")"
log "step2 host log tail: $(tail -n 3 "$home/state/.supervision-host.log" | tr '\n' '|')"
grep -q 'check: rearm-resurface' "$home/host.out" || { log "FAIL: host#1 did not pass the recovery wake to main"; exit 1; }
watcher_live || { log "FAIL: host#1 left no successor"; exit 1; }
m=$(marker); gen=${m##*:}
log "step2 marker=$(marker) successor_watcher=$(cat "$home/state/.watch.lock/pid") deliveries(rearm-resurface)=$(resurface_count)"

# 3. Main's handling turn: drain, nothing queued, turn ends without acknowledging.
FM_HOME="$home" "$DRAIN" > "$OUT/drain-main.out" 2> "$OUT/drain-main.err"
log "step3 drain stdout: $(tr '\n' '|' < "$OUT/drain-main.out")"
log "step3 drain stderr: $(tr '\n' '|' < "$OUT/drain-main.err")"
log "step3 marker=$(marker) queue_rows=$(queue_rows)   (main does NOT run the --ack-through 0 command)"

# 4. The Stop that ended the turn parks the host again: it takes the successor's cycle over.
t0=$(date +%s)
start_host
wait_until 300 grep -q '	take-over	' "$home/state/.supervision-host.log" || { log "FAIL: host#2 did not take over"; exit 1; }
log "step4 host#2 took over the left successor; watching 20s for a re-announcement..."
if wait_until 200 host_exited; then
  log "step4 host#2 EXITED after $(( $(date +%s) - t0 ))s rc=$(cat "$home/host.rc") host.out: $(tr '\n' '|' < "$home/host.out")"
  log "step4 host log tail: $(tail -n 2 "$home/state/.supervision-host.log" | tr '\n' '|')"
  log "step4 marker=$(marker) deliveries(rearm-resurface)=$(resurface_count)"
  if grep -q 'check: rearm-resurface' "$home/host.out"; then
    log "RESULT: LOOP REPRODUCED - the take-over after an unacknowledged empty handling turn re-announced check: rearm-resurface with nothing queued"
    exit 10
  fi
  log "RESULT: host#2 exited on something else"; exit 11
fi
log "step4 host#2 still parked after 20s; host.out=$(tr '\n' '|' < "$home/host.out")<end>"
log "step4 marker=$(marker) queue_rows=$(queue_rows) watcher_live=$(watcher_live && echo yes || echo no) deliveries(rearm-resurface)=$(resurface_count)"
log "step4 host log tail: $(tail -n 2 "$home/state/.supervision-host.log" | tr '\n' '|')"
[ "$(resurface_count)" = 1 ] || { log "RESULT: FAIL - rearm-resurface delivered $(resurface_count) times"; exit 12; }

# 5. The fresh cycle is still supervising: a real event surfaces to main.
printf 'needs-decision [at=%s]: which export format?\n' "$(date +%s)" >> "$home/state/demo.status"
wait_until 300 host_exited || { log "RESULT: FAIL - a real event after the handover never surfaced"; exit 13; }
log "step5 host#2 rc=$(cat "$home/host.rc") host.out: $(tr '\n' '|' < "$home/host.out")"
grep -q '^signal: .*demo.status' "$home/host.out" || { log "RESULT: FAIL - the close was not the real event"; exit 14; }
log "RESULT: PASS - the monitor handover stayed quiet with nothing queued, and the real event still surfaced"
exit 0
