#!/usr/bin/env bash
# Live reproduction of the captain's 2026-10-07 loop with the real product scripts.
# usage: live-handover-driver.sh <scripts-root> <lab-home> <out-dir> <queued-before 0|1>
set -u
ROOT=$1 LAB=$2 OUT=$3 QUEUED=${4:-0}
ARM="$ROOT/bin/fm-watch-arm.sh"; DRAIN="$ROOT/bin/fm-wake-drain.sh"
STATE="$LAB/state"
export FM_HOME="$LAB" FM_POLL=1 FM_SIGNAL_GRACE=0
mkdir -p "$OUT"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
wait_text() { local f=$1 t=$2 i=0; while [ $i -lt 600 ]; do grep -qF "$t" "$f" 2>/dev/null && return 0; sleep 0.1; i=$((i+1)); done; return 1; }
wait_exit() { local p=$1 i=0; while [ $i -lt 600 ]; do kill -0 "$p" 2>/dev/null || return 0; sleep 0.1; i=$((i+1)); done; return 1; }
alive() { kill -0 "$1" 2>/dev/null; }

log "scripts: $ROOT"; log "lab home: $LAB"; log "TMUX=${TMUX:-<unset>}"
# 1. A plain cycle, then the session exits: its watcher is stopped by TERM and publishes downtime.
"$ARM" --restart > "$OUT/arm1.out" 2>&1 & A1=$!
wait_text "$OUT/arm1.out" 'watcher: started pid=' || { log "arm1 never started: $(cat "$OUT/arm1.out")"; exit 1; }
if [ "$QUEUED" = 1 ]; then
  printf 'done: work main drains but never acknowledges\n' > "$STATE/queued.status"
  wait_exit "$A1" || { log "arm1 did not deliver the queued wake"; exit 1; }
  log "arm1 closed on a real wake: $(grep -E '^(signal|check|stale):' "$OUT/arm1.out")"
else
  W1=$(cat "$STATE/.watch.lock/pid"); kill -TERM "$W1"; wait_exit "$A1" || true
  log "arm1 watcher $W1 stopped by TERM (session exit); arm1 output: $(tr '\n' '|' < "$OUT/arm1.out")"
fi
log "marker after exit: $(cat "$STATE/.watcher-down" 2>/dev/null)"; log "queue rows: $(wc -l < "$STATE/.wake-queue" 2>/dev/null || echo 0)"

if [ "$QUEUED" = 0 ]; then
  # 2. The next session start re-arms: this recovery announcement is legitimate, exactly once.
  "$ARM" --restart > "$OUT/arm2-recovery.out" 2>&1 & A2=$!
  wait_exit "$A2" || { log "arm2 did not close"; exit 1; }
  log "arm2 (recovery after downtime) closed with: $(grep -E '^(signal|check|stale):' "$OUT/arm2-recovery.out")"
  PRED=$A2
else
  PRED=$A1
fi
log "marker after recovery: $(cat "$STATE/.watcher-down")"

# 3. The attended host leaves a handling successor for main (plain arm, predecessor named).
FM_WATCH_PREDECESSOR_ARM_PID=$PRED "$ARM" > "$OUT/arm3-successor.out" 2>&1 & A3=$!
wait_text "$OUT/arm3-successor.out" 'watcher: started pid=' || { log "successor never started: $(cat "$OUT/arm3-successor.out")"; exit 1; }
log "successor arm $A3: $(head -n1 "$OUT/arm3-successor.out")"

# 4. Main's handling turn drains and ends WITHOUT acknowledging (what the captain's log shows).
"$DRAIN" > "$OUT/drain.out" 2> "$OUT/drain.err"
log "drain stdout: $(tr '\n' '|' < "$OUT/drain.out")"; log "drain stderr: $(grep -E 'WAKE_ACK_REQUIRED' "$OUT/drain.err" | head -n1)"
log "marker after drain: $(cat "$STATE/.watcher-down")"; log "queue rows: $(wc -l < "$STATE/.wake-queue" 2>/dev/null || echo 0)"

# 5. The Stop that ended the turn takes the successor's cycle over.
"$ARM" --take-over "$A3" > "$OUT/arm4-takeover.out" 2>&1 & A4=$!
wait_text "$OUT/arm4-takeover.out" 'watcher: ' || true
log "take-over first line: $(head -n1 "$OUT/arm4-takeover.out")"
wait_exit "$A3" || true

# 6. Observe for 15s: before the fix the fresh cycle announced check: rearm-resurface within ~10s.
sleep 15
log "after 15s take-over arm $A4 alive=$(alive "$A4" && echo yes || echo no)"
log "take-over output: $(tr '\n' '|' < "$OUT/arm4-takeover.out")"
log "marker: $(cat "$STATE/.watcher-down")"; log "queue rows: $(wc -l < "$STATE/.wake-queue" 2>/dev/null || echo 0)"
log "cycle-exits log:"; cat "$STATE/.watch-cycle-exits.log"
log "deliveries log:"; cat "$STATE/.watch-deliveries.log" 2>/dev/null || echo "(none)"

if [ "$QUEUED" = 1 ] && ! alive "$A4"; then
  # Main re-drains, handles and acknowledges; the next arm then has nothing to recover.
  "$DRAIN" > "$OUT/redrain.out" 2> "$OUT/redrain.err"
  ACK=$(sed -n 's/.*--ack-through \([0-9]*\) --recovery-generation \([^ ]*\).*/\1 \2/p' "$OUT/redrain.err" | head -n1)
  log "redrain ack pair: $ACK"
  "$DRAIN" --ack-through ${ACK% *} --recovery-generation ${ACK#* } >> "$OUT/redrain.out" 2>&1 && log "acknowledged"
  "$ARM" --restart > "$OUT/arm5-after-ack.out" 2>&1 & A5=$!
  wait_text "$OUT/arm5-after-ack.out" 'watcher: started pid=' || true
  sleep 6
  log "arm5 after ack alive=$(alive "$A5" && echo yes || echo no) output: $(tr '\n' '|' < "$OUT/arm5-after-ack.out")"
  A4=$A5
fi

if alive "$A4"; then
  # 7. The quiet cycle is still supervising: a real event surfaces from it.
  printf 'done: a real event after the handover\n' > "$STATE/after-handover.status"
  wait_exit "$A4" && log "fresh cycle closed on the real event: $(grep -E '^(signal|check|stale):' "$OUT/arm4-takeover.out" "$OUT/arm5-after-ack.out" 2>/dev/null)" || log "fresh cycle did NOT surface the real event"
fi
# tidy: stop anything left
"$ARM" --stop >/dev/null 2>&1 || true
log "done"
