#!/usr/bin/env bash
# host-handover-queued.sh <repo-root> <label> - the adversarial twin: the handling turn ends with a row still queued
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
OUT="$EV/host-queued-$LABEL"
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

# 1. The host's first park: a real wake (a decision) is a main-only close, so the
#    host passes it to main, leaves a successor, and the row stays durable.
start_host
wait_until 300 watcher_live || { log "FAIL: host#1 never started a cycle"; exit 1; }
printf 'needs-decision [at=%s]: which export format?\n' "$(date +%s)" >> "$home/state/demo.status"
wait_until 300 host_exited || { log "FAIL: host#1 never passed the decision to main: $(cat "$home/state/.supervision-host.log")"; exit 1; }
log "step1 host#1 rc=$(cat "$home/host.rc") host.out: $(tr '\n' '|' < "$home/host.out")"
log "step1 marker=$(marker) queue_rows=$(queue_rows) successor_live=$(watcher_live && echo yes || echo no)"
log "step1 queue: $(cut -f2,3 "$home/state/.wake-queue" | tr '\n' '|')"
rows_before=$(queue_rows)
[ "$rows_before" -ge 1 ] || { log "FAIL: the delivered wake was not left durable"; exit 1; }

# 2. Main's handling turn drains the row and ends WITHOUT acknowledging it.
FM_HOME="$home" "$DRAIN" > "$OUT/drain-main.out" 2> "$OUT/drain-main.err"
log "step2 drain stdout: $(tr '\n' '|' < "$OUT/drain-main.out")"
log "step2 drain stderr: $(tr '\n' '|' < "$OUT/drain-main.err")"
log "step2 marker=$(marker) queue_rows=$(queue_rows)   (main does NOT acknowledge)"
grep -q 'demo.status' "$OUT/drain-main.out" || { log "FAIL: the drain did not present the row"; exit 1; }

# 3. The Stop that ended the turn parks the host again; it takes the successor over
#    and the fresh cycle must recover the unacknowledged row exactly once.
start_host
wait_until 300 grep -q '	take-over	' "$home/state/.supervision-host.log" || { log "FAIL: host#2 did not take over"; exit 1; }
wait_until 300 host_exited || { log "RESULT: FAIL - the take-over hid work main never acknowledged (host#2 still parked): marker=$(marker) queue_rows=$(queue_rows)"; exit 10; }
log "step3 host#2 rc=$(cat "$home/host.rc") host.out: $(tr '\n' '|' < "$home/host.out")"
log "step3 marker=$(marker) queue_rows=$(queue_rows) deliveries(rearm-resurface)=$(resurface_count) successor_live=$(watcher_live && echo yes || echo no)"
grep -q 'check: rearm-resurface' "$home/host.out" || { log "RESULT: FAIL - host#2 closed on something other than recovery"; exit 11; }
[ "$(queue_rows)" = "$rows_before" ] || { log "RESULT: FAIL - recovery changed the durable rows ($rows_before -> $(queue_rows))"; exit 12; }

# 4. Main re-drains, handles, acknowledges; the next park's take-over has nothing to recover.
FM_HOME="$home" "$DRAIN" > "$OUT/drain-redo.out" 2> "$OUT/drain-redo.err"
ack=$(sed -n 's/^WAKE_ACK_REQUIRED: after handling completes run bin\/fm-wake-drain.sh //p' "$OUT/drain-redo.err" | tail -1)
log "step4 re-drain presented: $(tr '\n' '|' < "$OUT/drain-redo.out") ack-cmd: $ack"
FM_HOME="$home" "$DRAIN" $ack || { log "FAIL: acknowledgement refused"; exit 1; }
log "step4 after ack: marker=$(marker) queue_rows=$(queue_rows)"
start_host
two_takeovers() { [ "$(grep -c '	take-over	' "$home/state/.supervision-host.log" 2>/dev/null)" -ge 2 ]; }
wait_until 300 two_takeovers || { log "FAIL: host#3 did not take over: $(tail -n 3 "$home/state/.supervision-host.log" | tr '\n' '|')"; exit 1; }
if wait_until 200 host_exited; then
  log "RESULT: FAIL - host#3 closed after the acknowledged recovery: $(tr '\n' '|' < "$home/host.out")"; exit 13
fi
log "step4 host#3 still parked after 20s: marker=$(marker) queue_rows=$(queue_rows) deliveries(rearm-resurface)=$(resurface_count)"
[ "$(resurface_count)" = 1 ] || { log "RESULT: FAIL - recovery announced $(resurface_count) times"; exit 14; }
log "RESULT: PASS - unacknowledged queued work resurfaced exactly once through the take-over, then the acknowledged handover stayed quiet"
exit 0
