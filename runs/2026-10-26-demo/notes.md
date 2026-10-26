# The demo run — what it is, what it shows, and what it cost

One unattended run of `agent.sh` against `deepseek-flash` at `reasoning_effort: low`, with no tool list anywhere in the request, one task, and no supervising. Its workspace was the current directory, and it is committed as the agent left it.

```
bash run.sh           # regenerates everything here; needs $DEEPSEEK_API_KEY and about 3 minutes
bash check-prefix.sh  # rebuilds every request from traj.md, then checks the cache; exits 0
```

`traj.md` is the copy of `session/traj.md` from that run; `meter.log` is its stderr; `session/` is the live record — raw block outputs, `req.<n>.json` and `res.<n>.json` for every turn, the compaction requests, and the job directories.

## What the trajectory shows, with the line to look at

| the milestone asks for | where it is |
|---|---|
| labels `User:` / `Bash:` / `Job:` and no other | four `User:` (the task, then three `/compact` commands), twenty `Bash:`, two `Job:` |
| a `Job:` that arrived while no block was running | line 402 (`job 1 exited 1 — note: 300-case depsort run`) and line 798 (`job 2 exited 0`, after the fix); both come from `bgrun` at line 396 and are delivered by the harness after the turn ends, with no block of the model's in between |
| one `[truncated:` line naming the full-output file | line 503 (`total 101 lines`, `session/raw/9.raw`) and line 848 (`total 302 lines`, `session/raw/19.raw`) |
| a compaction boundary with the rebuilt prompt | `<|compact|> kept=15` at line 444, `kept=30` at line 680, `kept=42` at line 987, each followed by the `<|summary|>` the next request was rebuilt from |
| a meter line on every turn | twenty-three `<|meter|>` lines: twenty turns and three compactions, each with `prompt`, `hit`, `miss`, `out` and the running total |
| the prefix never changed | `bash check-prefix.sh`: 20 requests rebuilt from the record and identical to what was sent, 23 requests in the meter, 3 boundaries, 19 checked, 0 failed |

The work: `work/depsort`, an awk tool that reads `a b` pairs ("a needs b") from a file or stdin and prints one valid build order, `cycle: …` plus exit 1 on a cycle. `work/gen.sh` generates cases and `work/check.awk` is an independent oracle.

The interesting part is the middle of the trajectory, not the end: the first 300-case run **failed 11 of 300** (line 402, `exited 1`), the model read the failures, found two real defects — a generator that emitted one-field lines when `n == 1`, and an awk `END` block that overrode a malformed-line `exit 2` — fixed both, kept the broken versions as `depsort.pre-fix` and `gen.sh.pre-fix`, and re-ran: 300 of 300. That is why there are two `Job:` messages rather than one. Re-run by hand afterwards: `base/lib/app` in order, `cycle: a b a` with status 1 on a cycle, empty input exits 0.

## What it cost

108,721 prompt tokens over 20 turns plus completion tokens; two background jobs, two truncations, three compactions, and it ended itself with a comment-only block at turn 20 instead of spending the turn budget.

## What it took to get a run this clean, since the record is the point

Six runs were paid for before this one — about 600k prompt tokens between them against 108k for this one — and each failure changed the tree rather than the story:

1. **40 turns, no result.** It wrapped blocks in markdown fences. In bash a pair of backticks is a command substitution, so the block ran twice, once with its own output as the command, and it spent a third of the run believing the harness re-evaluated stdout. Fixed by unfencing a fully wrapped block (`08ba308`) and saying why in the prompt.
2. **Hung on turn 2, four minutes, empty output.** A block was waiting for input nothing could type. Fixed by bounding every block at `AGENT_SH_BLOCK_TIMEOUT` and killing the hands' process group on expiry (`f066b8b`).
3. **Finished at turn 29 and then looped** — `echo finished`, re-verify, again — because the harness had no way to say "done". Fixed by reading a comment-only block as the stop (`7a758f3`), then by refusing to read an empty reply as one (`d73e614`).
4. **Two runs never showed a `Job:` or a truncation**, because the task did not demand them; both are now written into `task.txt` as checked steps.

Then the independent review (`P7`) found what this run's predecessor had hidden, and all of it was fixed before this run: a block could forge the slip by shadowing `printf`/`wc` (now the reporter uses `builtin`/`command` and a forged size is caught against the file), a job that never finished could hang the drain (now `AGENT_SH_JOB_WAIT`), `check-prefix.sh` could be fooled by an edited trajectory (it now rebuilds every request with `agent.sh --replay`), a stray `\x02` from a payload could fake a death (foreign records are now skipped), and the `Job:` message no longer comes with an invented `bgwait` turn — the record says exactly what happened: the harness waited, the model did not.

## What this does not claim

`deepseek-flash` still emits tool-call markup (`<|DSML|>`) with no tools declared, and turns 1–7 of this run are full of it being executed as bash and failing. The harness answers it with one bracketed note and the model works through it. That is the experiment, not a defect being hidden.

Whether the run is any good is the person's judgement, not an observation.
