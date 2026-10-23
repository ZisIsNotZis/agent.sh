# agent.sh — the roadmap

Why this file exists: this directory has a holder now, and one document has to say what the project is for, the one milestone the person set, what has been decided under `decide`, what is still open and where the evidence is.
Everything below is current unless it says otherwise; the design record behind it is `docs/design.md` and the direction that fixed the milestone is `docs/brief-m1.md`.
Work is placed here as nodes — one milestone, then packages, ordered by precedence, each with the observation that checks it off.

## What the project is for

An agent with no tools: the model's text is not parsed for tool calls, it is executed by one long-lived bash, and what bash printed returns as the next message.
The person's question is how good an agent gets that way without his supervising, so the proof is a trajectory from a real run and not a description of one.
His words, which fix the end and are quoted rather than paraphrased:

> a working agent (test and see trajectory), it should understand it's living in a different kind of harness than regular tool-based, that it got no tool and it's output is connected to bash directly, use comment/echo to talk to user.

The rest of that statement — labels, truncation, `/compact`, prefix matching, the demo conditions — is in `docs/brief-m1.md`, and the settled design that satisfies it is `docs/design.md`.

## M1 — the only milestone: a working unattended agent, with the trajectory as the proof

One milestone and no intermediate gate, as the person set it.
A package is not a milestone and this milestone is not split into "core" and "polish".
Status: **running**.

The four terms it is accepted on, each decidable by an observation rather than by opinion:

1. **Goal.** An agent that runs unattended against `deepseek-flash` at `reasoning_effort: low` on the completions API, holds no tool list anywhere in its prompt, and produces one real trajectory that a reader can follow turn by turn.
2. **Deliverable.** `agent.sh` (the harness, one bash file plus one `BASH_ENV` file), the system prompt it sends, `test/run.sh` for the invariants that cost nothing to check, and a committed run directory `runs/<date>-demo/` holding the trajectory, the meter log and the command that regenerates them.
3. **Acceptance, by observation.**
   - `bash test/run.sh` exits 0 — boundary, truncation, binary alarm, `bgrun`/`bgwait`, harness survival across a block that kills the hands. No metered calls.
   - `runs/<date>-demo/traj.md` exists and shows, in one read: label prefixes `User:` / `Bash:` / `Job:` and no other, at least one `Job:` message that arrived while the model had no block running, one `[truncated:` line pointing at a full-output file, one compaction boundary with the rebuilt prompt stated, and a meter line on every turn.
   - `bash runs/<date>-demo/check-prefix.sh` exits 0: for every turn after the first, `prompt_cache_hit_tokens ≥ prompt_tokens − (newly appended tail tokens + one 1024-token chunk)`, taken from the run's own `usage` field rather than from a code review.
   - A reviewer who did not write the harness reads the trajectory and the harness and returns one verdict; nothing here is called done by its producer.
4. **Not doing**, so an omission reads as a decision: no tool-call protocol (that is the project), no sandbox, no tmux, no pty, no Python, no bash plugin, no streaming in v0, no binary payload to the model, no second mechanism for timers or todos, no live output while a block runs, no force-push and no rewriting of `aeb66c9`.

One quality dimension is judged rather than observed and does not count as acceptance: whether the demo impresses the person.
It is his to give at the milestone and no evidence line can supply it.

## Packages

Order is precedence; a package starts when the one it waits on is landed.
Every package runs on idle machine time unless it is marked as spending metered tokens, and the demo package is the only one that does.

| # | package | waits on | status | what checks it off |
|---|---|---|---|---|
| P1 | the boundary loop with scripted input: blocks from a file through the `coproc`, slip by nonce, output by byte count, binary alarm, truncation to the session dir, labelled `Bash:` message, harness surviving the hands dying | — | done, `agent.sh` + `test/run.sh` | `bash test/run.sh` exits 0 |
| P2 | the hands' env: `BASH_ENV` carrying `bgrun`/`bgwait`, job state on disk, the note that rides the wake line, no polling when no job is pending | P1 | open | `bash test/run.sh` covers `bgrun` in one block reaped by `bgwait` in the next, and a session with no jobs sleeps zero times (counter printed) |
| P3 | the turn: completions call, trajectory appended in chat-ml, the meter line per turn, resume from the trajectory | P1, P2 | open (spends metered) | a two-turn run whose trajectory resumes byte-identically after a kill, and whose meter line carries `prompt_cache_hit_tokens` |
| P4 | the prompt: system prompt carrying the harness documentation the model has no tool list to learn from, and the `User:`/`Bash:`/`Job:` protocol | P2 | open | the system prompt file is greppable for the three labels and for `bgrun`/`bgwait`, and contains no tool schema |
| P5 | `/compact` as an appended message plus rebuild, and prefix stability across it | P3 | open (spends metered) | `check-prefix.sh` reports one boundary, and after it the hit/miss ratio returns to the pre-compaction shape |
| P6 | the demo scenario and the run directory: something the person could not have got from a copy-paste prompt, captured as `runs/<date>-demo/` | P3, P4, P5 | open (spends metered) | the M1 acceptance observations 3b and 3c |
| P7 | independent review of M1 | P6 | open | one verdict from a reviewer who did not write it |

## Decided, and under what assumption

This project runs at `decide`: the decisions the person would otherwise take are taken here and recorded as assumptions with what they cost, so he can overturn them one by one.
The four questions `docs/design.md` left open are answered here.

1. **Wake policy mid-turn — a finished job ends the turn.** The `Job:` message starts a new turn instead of being spliced into a block that is still being read.
   Cost of the assumption: one extra round trip per job completion, and the model sees a job's result one turn later than it could.
   Bought: no ambiguity about which block a result belongs to, and a trajectory that reads in order.
2. **The poll ships in v0.** Without it a turn that ends with jobs pending sleeps until the person types, which would make the async-arrival claim untestable in the demo.
   Cost: about fifteen lines of `read -t` loop in the one place polling is allowed, outside the model's turn.
3. **Truncation window is `--lines N`, default 100, and the full output is never copied.** The block's own raw file is the overflow file, so the header points at `$SESSION/raw/<n>.raw` and the model pages it with `sed -n`.
   Cost: the path leaks a session directory name into the conversation.
4. **`[status N]` is reported on every block, including a comment-only one.** It is the block's own `eval` status, so it is never a leftover.
   Cost: one line of noise per block, and a person who wanted silence from `#` blocks does not get it.

Also decided, because the design left it to the manager: the trajectory stays chat-ml text (no JSON in the hot path), a block's text is transported by a nonce-delimited heredoc and never by `printf %q`, and the session directory lives at `$PWD/.session/<utc-stamp>/` and is ignored by git.

## Open, and who holds it

- **The person's four settled questions are closed** by the decisions above; three of them were his and are now mine under `decide`.
- **The degree in the workspace register** is still `unknown`, because he has not stated one; it is not mine to invent and it does not block M1.
- **Licence and a runnable example** are missing from the front door for the same reason: neither is decided yet, and a placeholder would be worse than the absence. They are named in `README.md` as limits.

## Evidence

- `docs/design.md` — the settled design and every branch that lost, with the measurement that killed it.
- `docs/brief-m1.md` — the direction that fixed the milestone, the API facts measured on this machine, and the proposals root offered.
- `probes/` — five runnable measurements; `probes/README.md` says what each proves.
- `test/run.sh` — the invariant check P1 lands, and the one command the M1 acceptance names.
