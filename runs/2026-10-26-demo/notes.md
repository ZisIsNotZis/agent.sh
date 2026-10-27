# The demo run — what it is, what it shows, and what it cost

One unattended run of `agent.sh` against `deepseek-flash` at `reasoning_effort: low`, with no tool list anywhere in the request, one task, and no supervising. Its workspace was `seed/` copied into `work/`, and `work/` is committed as the agent left it.

```
bash run.sh           # regenerates everything here; needs $DEEPSEEK_API_KEY and about 3 minutes
bash check-prefix.sh  # rebuilds every request from traj.md, then checks the cache; exits 0
```

`traj.md` is the copy of `session/traj.md` from that run; `meter.log` is its stderr; `session/` is the live record — `blk/<n>.sh` (each block as sent), `slip/` (each block's status, as a file name), `raw/` (each block's output), `req.<n>.json` and `res.<n>.json`, the compaction requests, and the job directories.

The task is a maintenance job, not a green field: `report.txt` is a 401-line suite log with 185 failures, `src/order.sh` is missing its cycle branch, `src/suite.sh` is the judge and may not be edited, and `bench.sh` takes two minutes while a block is cut at 90 s — so the background job is a consequence of the machine, not a box to tick.

## What the trajectory shows, with the line to look at

| the milestone asks for | where it is |
|---|---|
| labels `User:` / `Bash:` / `Job:` and no other | two `User:` (the task, then one `/compact`), twenty `Bash:`, one `Job:` |
| a `Job:` that arrived while no block was running | line 263, `job 1 exited 0 — note: bench`, from `bgrun -n bench bash bench.sh 400` at line 246; the harness's drain waited, the model did not |
| one `[truncated:` line naming the full-output file | line 76 (`total 119 lines`, `session/raw/4.raw`) and line 545 (`total 111 lines`, `session/raw/14.raw`) |
| a compaction boundary with the rebuilt prompt | `<|compact|> kept=…` at line 475 with its `<|summary|>`, and every request after it rebuilt from that summary |
| a meter line on every turn | twenty-one `<|meter|>` lines: twenty turns and one compaction |
| the prefix never changed | `bash check-prefix.sh`: 20 requests rebuilt from the record and identical to what was sent, 21 requests in the meter, 1 boundary, 19 checked, 0 failed |

The work: it read the whole 401-line report through the truncation, found that `order.sh` had no cycle branch (185 of 400 cases were cyclic), added Kahn peeling plus a cycle walk, re-ran the suite to `400/400`, and wrote `RESULT.md` with the before/after numbers and the benchmark's. Re-run by hand afterwards: `work/src/suite.sh 400` → `SUMMARY total=400 pass=400 fail=0`; `printf 'a b\nb c\nc a\n' | work/src/order.sh /dev/stdin` → `cycle: a b c`, status 1.

## What it cost

83,724 prompt tokens over 20 turns plus completion tokens; one background job, two truncations, one compaction, and it ended itself with a comment-only block at turn 20 rather than spending the turn budget.

## What it took to get a run this clean, since the record is the point

Eight runs were paid for before this one. Each failure changed the tree rather than the story:

1. **Fenced blocks ran twice.** In bash a pair of backticks is a command substitution, so a fenced block ran, and then ran again with its own output as the command. Fixed by unfencing (`08ba308`), by dropping fence lines anywhere in a block (`e4a38f9`), and by saying why in the prompt.
2. **A block waiting on stdin hung the run** for four minutes. Fixed by bounding every block at `AGENT_SH_BLOCK_TIMEOUT` and killing the hands' process group on expiry (`f066b8b`).
3. **A block that opened with a fence turned into a nested `bash` reading the command stream**, which ate the slip line and cost another 300 s. Fixed by sourcing the block with stdin from `/dev/null` (`e4a38f9`), which also closed the "a block can steal its next command" hole.
4. **The run finished its task and then looped** on `echo finished`. Fixed by reading a comment-only block as the stop (`7a758f3`), and by refusing to read an empty reply as one (`d73e614`).
5. **A stray fence in the middle of a block silently killed a `bgrun` line**, so the run ended with no `Job:` and no truncation. Same fix as 1: a fence line is never a bash statement, wherever it sits.
6. **The task itself was the next failure.** Asking the model to `bgwait` its own job contradicts how the wake works — the harness delivers the `Job:`, and a run reaped by hand shows nothing — and asking it to "run something long" does not make anything long. The scenario now carries the constraint in the machine: a 90 s block bound and a 120 s benchmark.

Then the independent review (`P7`, two passes) found the boundary itself: the slip was a line of shell the block's own shell ran, so shadowing `builtin` let a block state any status. That is `P8`, and it is why the transport is now a file plus a redirection (`docs/design.md` D11).

## What this does not claim

`deepseek-flash` still emits tool-call markup with no tools declared, and the early turns of every run are full of it being executed as bash and failing. The harness answers it with one bracketed note and the model works through it. That is the experiment.

Whether the run is any good is not a question this file can answer. The harness's acceptance is that it has no bug, and `docs/design.md` D10 and D11 say exactly which residuals exist and how to reproduce them.
