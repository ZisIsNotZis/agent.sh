# All verified: order.sh has the missing cycle branch, syntax OK, executable.
# Smoke tests: chain -> c b a rc0; 3-cycle -> `cycle: a b c` rc1; self-loop -> `cycle: a` rc1; empty -> rc0.
# Proof: ./src/suite.sh 400 -> exit 0, SUMMARY total=400 pass=400 fail=0 (was pass=215 fail=185).
# Bench: 400 edges, wall 120013 ms, 0.0 edges/ms (job 1, exited 0).
# RESULT.md written with bug, proof command, suite numbers, bench numbers.
>"/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/slip/000f4716a9b9e056.$?"
