# The demo run — what it is, what it shows, and what it cost

One unattended run of `agent.sh` against `deepseek-flash` at `reasoning_effort: low`, with no tool list anywhere in the request.
The agent was given one task, no supervising, no repair by hand, and its workspace was `work/`, which is committed as it was left.

```
bash run.sh          # regenerates everything here; needs $DEEPSEEK_API_KEY
bash check-prefix.sh  # reads traj.md and checks the cache arithmetic; exits 0
```

`traj.md` is the copy of `session/traj.md` from that run; `meter.log` is its stderr; `session/` is the live record the harness wrote — raw block outputs, the request and response of every turn, and the job directories.

## What the trajectory shows, with the line to look at

| the milestone asks for | where it is |
|---|---|
| labels `User:` / `Bash:` / `Job:` and no other | three `User:` (the task, then two `/compact` commands), seventeen `Bash:`, one `Job:` |
| a `Job:` that arrived while no block was running | line 914, `job 1 exited 0 — note: 300-case-run`, from the `bgrun` at line 899 and the `bgwait`-only turn at line 911 |
| one `[truncated:` line naming the full-output file | line 1008, `total 301 lines, showing last 100; full output at …/session/raw/13.raw` |
| a compaction boundary with the rebuilt prompt | `<|compact|> kept=16` at line 580 and `kept=27` at line 917, each followed by the `<|summary|>` the next request was rebuilt from |
| a meter line on every turn | seventeen `<|meter|>` lines, each with `prompt`, `hit`, `miss`, `out` and the running total |
| the prefix never changed | `bash check-prefix.sh`: 19 requests, 2 boundaries, 16 checked, 0 failed |

The work itself: `work/bin/depsort`, a 38-line bash + awk topological sort that takes a file or stdin, deduplicates, keeps right-only packages, and reports a cycle as `cycle: …` with status 1.
`work/gen.sh` generates the cases and `work/check.sh` is an independent oracle; `work/logs/run300.log` has one line per case, 300 `PASS`, and `work/RESULT.md` is the agent's own account, which is its claim rather than ours — the tool was re-run by hand here afterwards and behaves as that file says.

## What it cost

86,366 prompt tokens over 17 turns, plus completion tokens; one `bgrun`, two compactions, one truncation. The free path is `bash test/run.sh`, which checks the same machinery with a stub model and spends nothing.

## What it took to get a run this clean, since the record is the point

Five runs were paid for before this one — 493,667 prompt tokens between them against 86,366 for this one — and each failure changed the tree rather than the story:

1. **40 turns, no result.** It wrapped blocks in markdown fences. In bash a pair of backticks is a command substitution, so ```` ```cmd``` ```` ran the block twice, once with its own output as the command, and it spent a third of the run believing the harness re-evaluated stdout. Fixed by unfencing a fully wrapped block (`08ba308`), and by telling the model why in the prompt.
2. **Hung on turn 2, four minutes, empty output.** A block was waiting for input nothing could type. Fixed by bounding every block at `AGENT_SH_BLOCK_TIMEOUT` and killing the hands' process group on expiry, which is why a timeout now reports `[status 124]` instead of silence (`f066b8b`).
3. **Finished its task at turn 29 and then looped** — `echo finished`, re-verify, again — because the harness had no way to say "done". Fixed by reading a block whose every line is a comment as the stop (`7a758f3`), and then by refusing to read an empty reply as one (`d73e614`), which a later run proved necessary by dying at turn 1 with 1,370 tokens spent.
4. **Two runs did the work but never showed the `Job:` and the truncation**, because the task did not demand them; both were kept only as evidence that the steps had to be written into the task, which they now are.

Everything in this directory was produced by the tree as committed at `d73e614`.

## What this does not claim

Whether the run is any good is the person's judgement, not an observation: the tables above are evidence, and nothing here turns them into a verdict.
