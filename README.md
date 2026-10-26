# agent.sh

[![licence: AGPL-3.0](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)

**An agent with no tools.** The model is never asked to produce a tool call: whatever it writes is handed to one long-lived bash and executed, and what that bash printed comes back to it as the next message. Two shell functions are injected; nothing else is.

The harness is the outer bash — it owns the API call, the trajectory, the labels, the truncation — and its hands are a `setsid bash` with no tty, reached over a `coproc`.

```sh
git clone https://github.com/ZisIsNotZis/agent.sh
cd agent.sh
bash test/run.sh                                   # the invariants, no API call, under a second
bash agent.sh --blocks examples/tour.sh            # the harness with the model's place taken by a file
```

Read `.session/<stamp>-<pid>/traj.md` afterwards: that is the conversation, turn by turn, in exactly the shape a model would have read.

## Why

Every agent framework answers "how does the model act?" by parsing its text for a tool call. This project deletes that question. The model's output *is* shell input, the shell already has files, jobs, pipes and state, and the only thing the harness has to solve is the boundary: knowing where a block ended and what its output was, when output arrives late from a background writer and the payload itself is untrusted bytes.

That boundary is arithmetic, not a search. The block is transported as a nonce-delimited heredoc; the output goes to a file; the control pipe carries one slip, `SENT <nonce> <exit> <bytes>`, followed by `\x02`; the outer bash reads exactly `<bytes>` and checks the count. No payload can impersonate a slip, because matching it would require guessing the nonce.

## What a turn looks like

`Bash:` starts every message from the hands, `[status N]` ends it, and each block's text is recorded beside its reply in the trajectory.

```
Bash: job 1 started, pid 2484919, log /…/jobs/1/log
[status 0]
Bash: the model keeps writing blocks while the job runs
[status 0]
Bash: job 1 exited 0
[status 0]
Bash: [truncated: total 150 lines, showing last 100; full output at /…/raw/6.raw]
line 51
…
[status 0]
```

Long output is truncated to the last `--lines N` (default 100) and the header names the block's own raw file, which the model pages with `sed -n` — the full output is never copied and never re-sent.

## The two functions

The hands get `BASH_ENV` and, through it, exactly two functions. Everything else is the shell it already is: `cd`, env, `&`, `wait -n -p`, files.

| function | what it does |
|---|---|
| `bgrun [-n note] cmd…` | starts `cmd` in the background, writes job state under `$AGENT_SH_JOBS/<seq>/` (`cmd`, `pid`, `note`, `log`), and returns at once |
| `bgwait` | reaps one finished job with `wait -n -p`, records its exit status, prints `job <seq> exited <status>` — `127` and `no jobs pending` when nothing is running |

A finished job starts a new turn rather than being spliced into a block still being read, so a trajectory stays readable in order, at the price of one round trip.

## Status

Running, and the harness is honest about where it is: **v0 makes no API call yet**. `--blocks <file>` puts a file where the model's output would go, which is why `test/run.sh` can check every invariant here for free.

- landed: the boundary loop, truncation, binary refusal, the harness surviving a block that kills its hands, `bgrun`/`bgwait` over disk job state, and a job that outlives the model's turn arriving as a `Job:` message carrying its note — `test/run.sh` covers it.
- next: the turn (completions call, trajectory appended, meter line, resume), the system prompt, `/compact`, then one real unattended run whose trajectory is the actual deliverable.

The milestone, its four terms, the not-doing list and every decision taken with its cost are in [`docs/roadmap.md`](docs/roadmap.md). Whether the run is any good is the one judgement left to a reader.

## Design, and what it cost

[`docs/design.md`](docs/design.md) records the settled design and every branch that lost, with the measurement that killed it; [`probes/`](probes/) re-runs those measurements in about a minute, including the two that are supposed to fail.

```sh
for p in probes/*.sh; do bash "$p"; done
```

## Not for

Anyone who wants a sandboxed, multi-user or networked agent service, a Python or TUI harness, or a tool-call protocol. Nothing is sandboxed on purpose: the harness sits outside everything the model can reach, and the model's hands are the shell state itself.

Requirements: bash 5.1+, coreutils, `iconv`. No dependency file, no build step — `test/run.sh` is plain bash.

## Licence

AGPL-3.0-only. See [`LICENSE`](LICENSE).

Copyright (C) 2026 ZisIsNotZis.
