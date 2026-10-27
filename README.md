# agent.sh

[![licence: AGPL-3.0](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)

**An agent with no tools.** The model is never asked to produce a tool call: whatever it writes is handed to one long-lived bash and executed, and what that bash printed comes back to it as the next message. Two shell functions are injected; nothing else is.

The harness is the outer bash — it owns the API call, the trajectory, the labels, the truncation — and its hands are a `setsid bash` with no tty, reached over a `coproc`.

```sh
git clone https://github.com/ZisIsNotZis/agent.sh
cd agent.sh
bash test/run.sh                                   # every invariant, no API call, about half a minute
bash agent.sh --blocks examples/tour.sh            # the harness with the model's place taken by a file
```

Read `.session/<stamp>-<pid>/traj.md` afterwards: that is the conversation, turn by turn, in exactly the shape a model would have read.

To let a real model drive it — `deepseek-flash` at `reasoning_effort: low` by default, about 800 prompt tokens per turn, so this costs a fraction of a cent:

```sh
export DEEPSEEK_API_KEY=…                          # deepseek.com; the completions API, no other key
bash agent.sh --task 'report the three largest files in this repo, with sizes' --max-turns 6
```

`--session DIR` pins where the run writes, `--resume` continues an existing session, `--lines N` sets the truncation window, `--compact-at N` compacts once a turn's prompt reaches `N` tokens, and `--stub FILE` replaces the API with a script for a free, deterministic run (that is what `test/run.sh` uses). Every turn appends a `<|meter|>` line to the trajectory with `prompt`, `hit`, `miss`, `out` and the running total, and prints the same line to stderr.

## Why

Every agent framework answers "how does the model act?" by parsing its text for a tool call. This project deletes that question. The model's output *is* shell input, the shell already has files, jobs, pipes and state, and the only thing the harness has to solve is the boundary: knowing where a block ended and what its output was, when output arrives late from a background writer and the payload itself is untrusted bytes.

That boundary is a file, not a stream. The harness writes the block into its own file and appends one line: `>"$slipdir/<nonce>.$?"` — a redirection with no command word, so the shell's own parser writes the block's status into a file name once the block is done. A redirection cannot be shadowed, replaced or intercepted by a function the block defines, so the report is the one thing in the protocol that a block cannot fake with a builtin. Output is read from the block's own file by byte count; a block that does not parse never reaches the shell at all and is reported as a syntax error with status 2.

The residual is the declared no-sandbox line and nothing more: a block can read its own source, so it can find the nonce and write a slip file itself. That is written down in [`docs/design.md`](docs/design.md) D11 with its reproduction instead of being claimed away — along with the one thing that is cheap to notice, that a block which shadows `.` breaks the *next* block's transport, which shows up as a timeout rather than as a silent success.

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

Running. The loop is closed and honest about what it has proven:

- landed: the boundary (nonce slip, byte count, arithmetic), truncation with the raw file named, binary refusal, the harness surviving a block that kills its hands, `bgrun`/`bgwait` over disk job state, a job outliving the model's turn and arriving as `Job:` with its note, the turn itself — completions call, reply executed as the block, meter line, resume that only ever appends — and a system prompt that teaches the protocol, since there is no tool list to teach it.
- next: `/compact` as an appended message plus a rebuilt prompt, then one real unattended run committed under `runs/<date>-demo/`, then review by someone who did not write it.

`bash test/run.sh` checks all of that with a stub model, free and deterministic — every invariant it prints. The one that matters most is `test/check-prefix.sh`, which does two things per run: it rebuilds every request from the trajectory alone and demands the sent request back byte for byte, then reads the run's own `usage` lines and fails if the prompt cache stopped matching. So "the prefix never changes" is arithmetic over the record, not a promise. The live path is one thin `curl` behind it.

The milestone, its four terms, the not-doing list and every decision taken with its cost are in [`docs/roadmap.md`](docs/roadmap.md). Whether the run is any good is the one judgement left to a reader.

## The demo run

[`runs/2026-10-26-demo/`](runs/2026-10-26-demo/) is one unattended run, committed as it happened: the trajectory, the meter, the requests, the workspace the agent left behind, and the command that regenerates all of it. Twenty turns, one background job it left for the harness to reap, two truncations, one compaction, 83,724 prompt tokens, and — the part that matters — `bash check-prefix.sh` rebuilds every request from the record and finds every prefix intact across it. `notes.md` points at the line each piece of evidence sits on, and says what the run cost to get.

## Design, and what it cost

[`docs/design.md`](docs/design.md) records the settled design and every branch that lost, with the measurement that killed it; [`probes/`](probes/) re-runs those measurements in about a minute, including the two that are supposed to fail.

```sh
for p in probes/*.sh; do bash "$p"; done
```

## Not for

Anyone who wants a sandboxed, multi-user or networked agent service, a Python or TUI harness, or a tool-call protocol. Nothing is sandboxed on purpose: the harness sits outside everything the model can reach, and the model's hands are the shell state itself.

Requirements: bash 5.1+, coreutils, `iconv`, `jq`, and `curl` for the live path. No dependency file, no build step — `test/run.sh` is plain bash.

A block is bounded at 300 s (`AGENT_SH_BLOCK_TIMEOUT`), because a block that reads stdin would otherwise hang an unattended run forever; the price is the shell state it built, and the message says so. The wait for a background job is bounded too (`AGENT_SH_JOB_WAIT`, 600 s): a job that outlives it is reported as still running and left for a later turn instead of ending the run.

## Licence

AGPL-3.0-only. See [`LICENSE`](LICENSE).

Copyright (C) 2026 ZisIsNotZis.
