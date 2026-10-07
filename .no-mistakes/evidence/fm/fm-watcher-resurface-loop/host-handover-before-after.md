# Monitor handover loop: before vs after (real supervision host, watcher, arm, drain against a disposable home)

## Fixed tree (a211c97e) - host-handover-loop.sh
```
[12:31:27] === fixed: repo=/Users/daniel.martin/.no-mistakes/worktrees/ec5c263228f4/01M4B1K0FGC8S1VTZ8HQK1MZYM ===
[12:31:34] step1 after watcher TERM: marker=pending:downtime:14686.1791372692.ibuvpK queue_rows=0
[12:31:47] step2 host#1 rc=0 host.out: watcher: started pid=20839 (beacon fresh)|check: rearm-resurface|
[12:31:47] step2 host log tail: 1791372699	start	gen=host-19498-1791372697	primary=claude|1791372702	pass-through	attended	main-only	check: rearm-resurface|
[12:31:47] step2 marker=announced:downtime:14686.1791372692.ibuvpK successor_watcher=24079 deliveries(rearm-resurface)=1
[12:32:02] step3 drain stdout: 
[12:32:02] step3 drain stderr: WAKE_ACK_REQUIRED: after handling completes run bin/fm-wake-drain.sh --ack-through 0 --recovery-generation 14686.1791372692.ibuvpK|
[12:32:02] step3 marker=announced:handling:14686.1791372692.ibuvpK queue_rows=0   (main does NOT run the --ack-through 0 command)
[12:32:08] step4 host#2 took over the left successor; watching 20s for a re-announcement...
[12:32:48] step4 host#2 still parked after 20s; host.out=watcher: started pid=39760 (beacon fresh)|<end>
[12:32:48] step4 marker=announced:handling:14686.1791372692.ibuvpK queue_rows=0 watcher_live=yes deliveries(rearm-resurface)=1
[12:32:48] step4 host log tail: 1791372728	start	gen=host-35817-1791372726	primary=claude|1791372728	take-over	arm=23922|
[12:33:12] step5 host#2 rc=0 host.out: watcher: started pid=39760 (beacon fresh)|signal: /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-host-handover.qJFXPz/home/state/demo.status|
[12:33:13] RESULT: PASS - the monitor handover stayed quiet with nothing queued, and the real event still surfaced
```

## Base commit (47aff866) - same script
```
[12:33:16] === base: repo=/private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp ===
[12:33:24] step1 after watcher TERM: marker=pending:downtime:85030.1791372801.x4TRh6 queue_rows=0
[12:34:31] step2 host#1 rc=0 host.out: watcher: started pid=94220 (beacon fresh)|check: rearm-resurface|
[12:34:32] step2 host log tail: 1791372809	start	gen=host-91846-1791372808	primary=claude|1791372848	pass-through	attended	main-only	check: rearm-resurface|
[12:34:33] step2 marker=announced:downtime:85030.1791372801.x4TRh6 successor_watcher=18250 deliveries(rearm-resurface)=1
[12:34:40] step3 drain stdout: 
[12:34:40] step3 drain stderr: WAKE_ACK_REQUIRED: after handling completes run bin/fm-wake-drain.sh --ack-through 0 --recovery-generation 85030.1791372801.x4TRh6|
[12:34:40] step3 marker=announced:handling:85030.1791372801.x4TRh6 queue_rows=0   (main does NOT run the --ack-through 0 command)
[12:34:42] step4 host#2 took over the left successor; watching 20s for a re-announcement...
[12:35:01] step4 host#2 EXITED after 21s rc=0 host.out: watcher: started pid=43871 (beacon fresh)|check: rearm-resurface|
[12:35:01] step4 host log tail: 1791372882	take-over	arm=15390|1791372890	pass-through	attended	main-only	check: rearm-resurface|
[12:35:01] step4 marker=announced:downtime:85030.1791372801.x4TRh6 deliveries(rearm-resurface)=2
[12:35:01] RESULT: LOOP REPRODUCED - the take-over after an unacknowledged empty handling turn re-announced check: rearm-resurface with nothing queued
```

## Fixed tree - adversarial twin with a row still queued (host-handover-queued.sh)
```
[12:38:28] === fixed: repo=/Users/daniel.martin/.no-mistakes/worktrees/ec5c263228f4/01M4B1K0FGC8S1VTZ8HQK1MZYM ===
[12:38:37] step1 host#1 rc=0 host.out: watcher: started pid=91171 (beacon fresh)|signal: /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-host-handover.bMIQgW/home/state/demo.status|
[12:38:37] step1 marker=announced:downtime:91171.1791373113.0AYjqR queue_rows=2 successor_live=yes
[12:38:37] step1 queue: 1	signal|2	signal|
[12:38:39] step2 drain stdout: 1791373113	2	signal	demo.status	needs-decision: /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-host-handover.bMIQgW/home/state/demo.status|wake annotation: latest wake-EVENT observed at drain, not current state: demo.status: needs-decision [at=1791373110]: which export format?|OPEN DECISIONS (still open, folded from the durable status logs - not just the latest line):|demo needs-decision: which export format?|OPEN DECISIONS: close one by answering it: bin/fm-send.sh <task> --resolve-key <key> '<answer>'|
[12:38:39] step2 drain stderr: WAKE_ACK_REQUIRED: after handling completes run bin/fm-wake-drain.sh --ack-through 2 --recovery-generation 91171.1791373113.0AYjqR|WARNING: queued wakes pending - drain them with bin/fm-wake-drain.sh before anything else.|
[12:38:39] step2 marker=announced:handling:91171.1791373113.0AYjqR queue_rows=2   (main does NOT acknowledge)
[12:38:52] step3 host#2 rc=0 host.out: watcher: started pid=2549 (beacon fresh)|check: rearm-resurface|
[12:38:53] step3 marker=announced:downtime:91171.1791373113.0AYjqR queue_rows=2 deliveries(rearm-resurface)=1 successor_live=yes
[12:38:58] step4 re-drain presented: 1791373113	2	signal	demo.status	needs-decision: /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-host-handover.bMIQgW/home/state/demo.status|OPEN DECISIONS (still open, folded from the durable status logs - not just the latest line):|demo needs-decision: which export format?|OPEN DECISIONS: close one by answering it: bin/fm-send.sh <task> --resolve-key <key> '<answer>'| ack-cmd: --ack-through 2 --recovery-generation 91171.1791373113.0AYjqR
[12:38:59] step4 after ack: marker=acked:handling:91171.1791373113.0AYjqR queue_rows=0
[12:39:46] step4 host#3 still parked after 20s: marker=acked:handling:91171.1791373113.0AYjqR queue_rows=0 deliveries(rearm-resurface)=1
[12:39:47] RESULT: PASS - unacknowledged queued work resurfaced exactly once through the take-over, then the acknowledged handover stayed quiet
```

## Supervision host ledger after the fixed run
```
1791372699	start	gen=host-19498-1791372697	primary=claude
1791372702	pass-through	attended	main-only	check: rearm-resurface
1791372728	start	gen=host-35817-1791372726	primary=claude
1791372728	take-over	arm=23922
1791372786	pass-through	attended	main-only	signal: /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-host-handover.qJFXPz/home/state/demo.status
```

## Supervision host ledger after the base run (second pass-through of check: rearm-resurface = the loop)
```
1791372809	start	gen=host-91846-1791372808	primary=claude
1791372848	pass-through	attended	main-only	check: rearm-resurface
1791372882	start	gen=host-40246-1791372881	primary=claude
1791372882	take-over	arm=15390
1791372890	pass-through	attended	main-only	check: rearm-resurface
```

## Watch-cycle exits ledger, base run
```
arm_pid=84634	watcher_pid=85030	origin=started	started_at=1791372797	ended_at=1791372801	exit_code=143	signal=TERM	reason=signal-exit	beacon_age=1	lock_before=pid:85030|identity:Wed Oct  7 12:33:17 2026     bash /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp/bin/fm-watch.sh	lock_after=pid:none|identity:none	successor=none
arm_pid=93498	watcher_pid=94220	origin=started	started_at=1791372811	ended_at=1791372818	exit_code=0	signal=none	reason=actionable-check	beacon_age=1	lock_before=pid:94220|identity:Wed Oct  7 12:33:31 2026     bash /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp/bin/fm-watch.sh	lock_after=pid:none|identity:none	successor=started:18250
arm_pid=15390	watcher_pid=18250	origin=started	started_at=1791372856	ended_at=1791372883	exit_code=143	signal=TERM	reason=signal-exit	beacon_age=1	lock_before=pid:18250|identity:Wed Oct  7 12:34:15 2026     bash /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp/bin/fm-watch.sh	lock_after=pid:none|identity:none	successor=none
arm_pid=41510	watcher_pid=18250	origin=attached	started_at=1791372882	ended_at=1791372884	exit_code=unknown	signal=unknown	reason=taken-over	beacon_age=2	lock_before=pid:18250|identity:Wed Oct  7 12:34:15 2026     bash /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp/bin/fm-watch.sh	lock_after=pid:none|identity:none	successor=started:43871
arm_pid=41510	watcher_pid=43871	origin=started	started_at=1791372884	ended_at=1791372886	exit_code=0	signal=none	reason=actionable-check	beacon_age=1	lock_before=pid:43871|identity:Wed Oct  7 12:34:44 2026     bash /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp/bin/fm-watch.sh	lock_after=pid:none|identity:none	successor=started:47505
arm_pid=47323	watcher_pid=47505	origin=started	started_at=1791372891	ended_at=1791372902	exit_code=143	signal=TERM	reason=signal-exit	beacon_age=4	lock_before=pid:47505|identity:Wed Oct  7 12:34:50 2026     bash /private/var/folders/sj/wkdqwx054mb5c2ffqzxr7yvh0000gn/T/fm-base-47aff866.tCZmPp/bin/fm-watch.sh	lock_after=pid:none|identity:none	successor=none
```
