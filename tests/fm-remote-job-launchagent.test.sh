#!/usr/bin/env bash
# Darwin ensure and LaunchAgent concurrency tests through the executable library.
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP_ROOT=$(fm_test_tmproot fm-remote-job-launchagent)
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
REMOTE_ROOT="$TMP_ROOT/remote-root"
ACCOUNT_HOME="$TMP_ROOT/account"
STATE_ROOT="$TMP_ROOT/state"
STUB_BIN="$TMP_ROOT/stub-bin"
LAUNCH_LOG="$TMP_ROOT/launchctl.log"
SWEEP_GATE="$TMP_ROOT/sweep-gate"
WORKER_PID=
mkdir -p "$REMOTE_ROOT/bin" "$ACCOUNT_HOME" "$STUB_BIN" "$REMOTE_ROOT/.seq-claims/1"
cp "$ROOT/bin/fm-remote-job-lib.sh" "$ROOT/bin/fm-remote-job-worker.sh" "$REMOTE_ROOT/bin/"
printf 'fixture\n' > "$REMOTE_ROOT/AGENTS.md"
chmod +x "$REMOTE_ROOT/bin/fm-remote-job-worker.sh"
git -C "$REMOTE_ROOT" init -q -b main
git -C "$REMOTE_ROOT" config user.email test@example.com
git -C "$REMOTE_ROOT" config user.name Test
git -C "$REMOTE_ROOT" add AGENTS.md bin
git -C "$REMOTE_ROOT" commit -qm 'launchagent fixture'
REAL_RMDIR=$(command -v rmdir)
cat > "$STUB_BIN/rmdir" <<'SH'
#!/bin/bash
printf 'rmdir %s\n' "$*" >> "$FM_TEST_STAT_LOG"
last=${!#}
case "$last" in
  */.seq-claims/[0-9]*)
    if [ -n "${FM_TEST_SWEEP_GATE:-}" ] && mkdir "$FM_TEST_SWEEP_GATE.once" 2>/dev/null; then
      : > "$FM_TEST_SWEEP_GATE"
      /bin/sleep 12
    fi
    ;;
esac
exec "$FM_TEST_REAL_RMDIR" "$@"
SH
cat > "$STUB_BIN/launchctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$FM_TEST_LAUNCH_LOG"
case "${1:-}" in
  print)
    case "${2:-}" in
      gui/[0-9]*)
        if [[ "$2" == gui/*/dev.firstmate.remote-job ]]; then
          [ -f "$FM_TEST_LOADED" ] || exit 1
          printf '%s\n' "dev.firstmate.remote-job $FM_TEST_WORKER $FM_TEST_PLIST"
        else
          exit 0
        fi
        ;;
      *) exit 1 ;;
    esac
    ;;
  bootout) rm -f "$FM_TEST_LOADED" ;;
  bootstrap) : > "$FM_TEST_LOADED" ;;
  kickstart)
    HOME="$FM_TEST_ACCOUNT" FM_ROOT_OVERRIDE="$FM_TEST_ROOT" \
      FM_REMOTE_JOB_STATE_ROOT="$FM_TEST_STATE" FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux \
      "$FM_TEST_WORKER" >> "$FM_TEST_WORKER_LOG" 2>&1 &
    child=$!
    for _ in $(seq 1 200); do
      [ -f "$FM_TEST_STATE/worker.ready" ] && break
      /bin/sleep 0.05
    done
    [ -f "$FM_TEST_STATE/worker.ready" ] || exit 1
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$STUB_BIN/rmdir" "$STUB_BIN/launchctl"
export PATH="$STUB_BIN:$PATH"
export FM_TEST_REAL_RMDIR="$REAL_RMDIR" FM_TEST_LAUNCH_LOG="$LAUNCH_LOG" FM_TEST_STAT_LOG="$TMP_ROOT/rmdir.log"
export FM_TEST_ROOT="$REMOTE_ROOT" FM_TEST_ACCOUNT="$ACCOUNT_HOME"
export FM_TEST_WORKER="$REMOTE_ROOT/bin/fm-remote-job-worker.sh"
export FM_TEST_WORKER_LOG="$TMP_ROOT/worker.log" FM_TEST_STATE="$STATE_ROOT"
export FM_TEST_LOADED="$TMP_ROOT/launchagent.loaded"
export FM_TEST_PLIST="$ACCOUNT_HOME/Library/LaunchAgents/dev.firstmate.remote-job.plist"
export FM_TEST_SWEEP_GATE="$SWEEP_GATE"

cleanup() {
  if [ -n "$WORKER_PID" ]; then
    fm_remote_job_stop_worker_tree "$WORKER_PID" >/dev/null 2>&1 || true
  fi
  if [ -f "$STATE_ROOT/worker.lock/pid" ]; then
    fm_remote_job_stop_worker_tree "$(cat "$STATE_ROOT/worker.lock/pid")" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

export FM_REMOTE_JOB_STATE_ROOT="$STATE_ROOT" FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux
. "$ROOT/bin/fm-remote-job-lib.sh"
fm_remote_job_prepare_state "$ACCOUNT_HOME"
fm_remote_job_write_launchagent "$REMOTE_ROOT" "$ACCOUNT_HOME"
mkdir -p "$STATE_ROOT/.seq-claims/1"
touch -t 200001010000 "$STATE_ROOT/.seq-claims/1"
: > "$FM_TEST_LOADED"
HOME="$ACCOUNT_HOME" FM_ROOT_OVERRIDE="$REMOTE_ROOT" FM_REMOTE_JOB_STATE_ROOT="$STATE_ROOT" \
  FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux FM_TEST_SWEEP_GATE="$SWEEP_GATE" \
  "$FM_TEST_WORKER" > "$TMP_ROOT/sweep-worker.log" 2>&1 &
WORKER_PID=$!
for _ in $(seq 1 200); do
  [ -f "$SWEEP_GATE" ] && [ -f "$STATE_ROOT/worker.ready" ] && break
  /bin/sleep 0.05
done
[ -f "$SWEEP_GATE" ] || { printf 'worker log:\n'; cat "$TMP_ROOT/sweep-worker.log"; printf 'rmdir log:\n'; cat "$TMP_ROOT/rmdir.log"; printf 'state:\n'; ls -la "$STATE_ROOT"; ps -p "$WORKER_PID" -o pid=,stat=,command= || true; fail 'the real worker did not enter its sequence-claim sweep'; }
[ -f "$STATE_ROOT/worker.ready" ] || fail 'the worker did not publish readiness before its slow sweep'
/bin/sleep 11
if ! ( FM_REMOTE_JOB_STATE_ROOT="$STATE_ROOT" FM_REMOTE_JOB_PLATFORM_OVERRIDE=Darwin \
  fm_remote_job_ensure_worker "$REMOTE_ROOT" "$ACCOUNT_HOME" ); then
  fail "ensure failed during a slow sequence-claim sweep: $FM_REMOTE_JOB_ERROR"
fi
! grep -q '^bootout ' "$LAUNCH_LOG" || fail 'ensure booted out a healthy worker during the slow sweep'
pass 'a slow sequence-claim sweep keeps readiness fresh and cannot trigger a LaunchAgent bootout'
/bin/sleep 2

# A clean LaunchAgent start followed by concurrent ensures must have one reload
# sequence; the second caller rechecks readiness after acquiring the mutex.
fm_remote_job_stop_worker_tree "$WORKER_PID" || fail 'the sweep fixture worker did not stop'
WORKER_PID=
rm -rf -- "$STATE_ROOT" "$ACCOUNT_HOME/Library" "$FM_TEST_LOADED" "$LAUNCH_LOG"
mkdir -p "$ACCOUNT_HOME"
fm_remote_job_prepare_state "$ACCOUNT_HOME"
ensure_darwin() (
  FM_REMOTE_JOB_STATE_ROOT="$STATE_ROOT" FM_REMOTE_JOB_PLATFORM_OVERRIDE=Darwin \
    fm_remote_job_ensure_worker "$REMOTE_ROOT" "$ACCOUNT_HOME"
)
ensure_darwin > "$TMP_ROOT/ensure-a.out" 2>&1 &
first=$!
ensure_darwin > "$TMP_ROOT/ensure-b.out" 2>&1 &
second=$!
if ! wait "$first"; then cat "$TMP_ROOT/ensure-a.out" "$TMP_ROOT/ensure-b.out"; fail 'the first concurrent Darwin ensure failed'; fi
if ! wait "$second"; then cat "$TMP_ROOT/ensure-a.out" "$TMP_ROOT/ensure-b.out"; fail 'the second concurrent Darwin ensure failed'; fi
[ "$(grep -c '^bootout ' "$LAUNCH_LOG")" -eq 1 ] \
  || fail 'concurrent callers ran multiple LaunchAgent bootouts'
[ "$(grep -c '^bootstrap ' "$LAUNCH_LOG")" -eq 1 ] \
  || fail 'concurrent callers bootstrapped the agent more than once'
[ "$(grep -c '^kickstart ' "$LAUNCH_LOG")" -eq 1 ] \
  || fail 'concurrent callers kickstarted multiple workers'
WORKER_PID=$(cat "$STATE_ROOT/worker.pid")
pass 'concurrent Darwin ensures serialize reloads and adopt the first fresh worker'

# Model an orphan that remains a verified live lock owner after its code changes
# and is absent from launchd's service record.
old_pid=$WORKER_PID
printf '\n# updated fixture code\n' >> "$REMOTE_ROOT/bin/fm-remote-job-worker.sh"
git -C "$REMOTE_ROOT" add bin/fm-remote-job-worker.sh
git -C "$REMOTE_ROOT" commit -qm 'updated worker identity'
rm -f "$FM_TEST_LOADED"
: > "$LAUNCH_LOG"
if ! ( FM_REMOTE_JOB_STATE_ROOT="$STATE_ROOT" FM_REMOTE_JOB_PLATFORM_OVERRIDE=Darwin \
  fm_remote_job_ensure_worker "$REMOTE_ROOT" "$ACCOUNT_HOME" ); then
  fail "Darwin did not recover the verified orphaned worker: $FM_REMOTE_JOB_ERROR"
fi
new_pid=$(cat "$STATE_ROOT/worker.pid")
[ "$new_pid" != "$old_pid" ] || fail 'Darwin retained the orphan running stale code'
! kill -0 "$old_pid" 2>/dev/null || fail 'the stale orphan remained alive after identity-safe replacement'
[ "$(grep -c '^bootout ' "$LAUNCH_LOG")" -eq 1 ] \
  || fail 'orphan recovery did not perform exactly one LaunchAgent bootout'
fm_remote_job_worker_identity_matches "$REMOTE_ROOT" "$ACCOUNT_HOME" \
  || fail 'the replacement worker identity does not match current code'
WORKER_PID=$new_pid
pass 'Darwin stops a verified untracked stale-code owner and starts the current worker'

printf 'ALL TESTS PASSED\n'
