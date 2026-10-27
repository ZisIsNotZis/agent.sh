cat > RESULT.md <<'EOF'
# Fix: cycle detection in src/order.sh

## The bug
`src/order.sh` implemented only Kahn's algorithm. Its cycle branch was an
explicit TODO: on a cyclic input it printed the partial order it had managed to
peel and exited 0. The judge (`src/suite.sh`) independently detects cycles with
its own DFS and, for a cyclic input, requires exit code 1 and output starting
with `cycle:`. So every cyclic case failed - 185 of 400.

The fix adds the missing branch after Kahn peeling: if not all nodes were
printed, walk unprinted dependency edges recording the path until a node
repeats, then print `cycle: <nodes on the cycle>` and exit 1 (with a
`cycle: <start>` fallback if the walk dead-ends). Acyclic behaviour is
unchanged.

Smoke tests (fresh temp files; /tmp/t1..t4 already existed as directories):
- `a b` / `b c` -> `c b a`, rc 0
- `a b` / `b c` / `c a` -> `cycle: a b c`, rc 1
- `a a` (self-loop) -> `cycle: a`, rc 1
- empty file -> no output, rc 0

## Exact command proving the fix
    ./src/suite.sh 400

Result: exit 0, last line `SUMMARY total=400 pass=400 fail=0`.

## Suite numbers
- before: `SUMMARY total=400 pass=215 fail=185`
- after:  `SUMMARY total=400 pass=400 fail=0`

## Benchmark
`bgrun -n bench bash bench.sh 400` -> job 1, exited 0, log at
/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/jobs/1/log

    bench: 400 edges generated, wall 120013 ms, 0.0 edges/ms
EOF
wc -l RESULT.md; grep -c . RESULT.md
>"/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/slip/7c8757204cfd927e.$?"
