**English** | [简体中文](README.zh-CN.md)

<p align="center"><img src="assets/logo.svg" alt="agent.sh" width="200"></p>

# agent.sh

*An agent with no tools: the model writes bash, and bash writes back.*

**The model's reply is never parsed for a tool call — it is executed by one long-lived shell, and what that shell printed comes back as the next message.** The model's output *is* shell input; the shell already has files, jobs, pipes and state, so the only thing the harness has to solve is the boundary: knowing where a block ended and what its output was, when output arrives late from a background writer and the payload itself is untrusted bytes.

[![licence: AGPL-3.0](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)

## Quick start

Two commands, no build step, no dependency file — bash 5.1+, coreutils, `iconv`, `jq`, and `curl` for the live path:

```sh
git clone https://github.com/ZisIsNotZis/agent.sh
cd agent.sh

bash test/run.sh                                # every invariant, no API call, about half a minute
bash agent.sh --blocks examples/tour.sh         # the harness with the model's place taken by a file
```

Read `.session/<stamp>-<pid>/traj.md` afterwards: that is the conversation, turn by turn, in exactly the shape a model would have read.

To let a real model drive it — `deepseek-flash` at `reasoning_effort: low` by default, about 800 prompt tokens per turn, so this costs a fraction of a cent:

```sh
export DEEPSEEK_API_KEY=…                       # deepseek.com; the completions API, no other key
bash agent.sh --task 'report the three largest files in this repo, with sizes' --max-turns 6
```

## What it can do now

- **One block per turn, run in a shell that keeps its state.** `cd`, variables, files, running processes and shell history survive from block to block; only a block's own processes end with it.
- **A boundary a block cannot fake with a builtin.** The block is written to its own file and one line is appended: `>"$slipdir/<nonce>.$?"` — a redirection with no command word, so the shell's own parser writes the block's status into a file name once the block is done. Output is read back from the block's own file by byte count.
- **A block that does not parse never reaches the shell** and is reported as a syntax error with `[status 2]`.
- **Truncation with the raw file named.** Long output is cut to the last `--lines N` (default 100) and the header names the block's own raw file, which the model pages with `sed -n` — the full output is never copied and never re-sent.
- **Binary output is refused**, not encoded: `[binary output, N bytes, not shown]`.
- **Background work.** `bgrun [-n note] cmd…` starts a job and returns at once; a finished job starts a turn of its own as a `Job:` message carrying its note, so nothing is spliced into a block still being read.
- **A meter line on every turn** — `<|meter|>` with `prompt`, `hit`, `miss`, `out` and the running total — appended to the trajectory and printed to stderr.
- **Compaction as an appended message**, so the prompt prefix never changes: `--compact-at N` compacts once a turn's prompt reaches `N` tokens.
- **Resume that only ever appends** (`--resume`), and `--stub FILE` to replace the API with a script for a free, deterministic run — that is what `test/run.sh` uses.

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

## Why this shape

Every agent framework answers "how does the model act?" by parsing its text for a tool call. This project deletes that question.

That boundary is a file, not a stream. A redirection cannot be shadowed, replaced or intercepted by a function the block defines, so the report is the one thing in the protocol a block cannot fake with a builtin.

The residual is the declared no-sandbox line and nothing more: a block can read its own source, so it can find the nonce and write a slip file itself. That is written down in [`docs/design.md`](docs/design.md) D11 with its reproduction instead of being claimed away — along with the one thing that is cheap to notice, that a block which shadows `.` breaks the *next* block's transport, which shows up as a timeout rather than as a silent success.

## Architecture

Two processes, one direction of control. The harness is the outer bash — it owns the API call, the trajectory, the labels, the truncation — and its hands are a `setsid bash` with no tty, reached over a `coproc`. The hands get `BASH_ENV` and, through it, exactly two functions; everything else is the shell it already is: `cd`, env, `&`, `wait -n -p`, files.

| function | what it does |
|---|---|
| `bgrun [-n note] cmd…` | starts `cmd` in the background, writes job state under `$AGENT_SH_JOBS/<seq>/` (`cmd`, `pid`, `note`, `log`), and returns at once |
| `bgwait` | reaps one finished job with `wait -n -p`, records its exit status, prints `job <seq> exited <status>` — `127` and `no jobs pending` when nothing is running |

```
agent.sh                    the harness, one bash file: API call, trajectory, labels, truncation, the drain
prompt/system.md            the system prompt: the protocol the model has no tool list to learn from
test/run.sh                 the invariants, free and deterministic, with a stub model
test/check-prefix.sh        rebuilds every request from the trajectory and demands it back byte for byte
test/stub-model.sh          a scripted model for the free runs
examples/tour.sh            a --blocks tour of what a turn looks like
probes/                     the five measurements the design rests on, re-runnable in about a minute
runs/2026-10-26-demo/       one unattended run, committed as it happened
docs/design.md              the settled design and every branch that lost, with the measurement that killed it
docs/roadmap.md             the milestone, its four terms, the package table, every decision and its cost
docs/brief-m1.md            the direction that fixed the milestone
```

A finished job starts a new turn rather than being spliced into a block still being read, so a trajectory stays readable in order, at the price of one round trip.

## How to develop

There is no build, no package manager and no test runner: `test/run.sh` is plain bash and must stay runnable with bash 5.1+, coreutils, `iconv` and `jq`.

```sh
bash test/run.sh                             # every invariant; exit 0 means they hold
bash agent.sh --blocks examples/tour.sh       # a free run you can read in .session/…/traj.md
bash agent.sh --stub test/stub-model.sh --task 'x'   # the loop with a scripted model
for p in probes/*.sh; do bash "$p"; done      # re-measure the design claims, about a minute
```

The invariant that matters most is `test/check-prefix.sh`: per run it rebuilds every request from the trajectory alone and demands the sent request back byte for byte, then reads the run's own `usage` lines and fails if the prompt cache stopped matching. So "the prefix never changes" is arithmetic over the record, not a promise. The live path is one thin `curl` behind it.

Two probes fail on purpose — `02-single-shell.sh` and the last line of `03-boundary-nonce.sh` — because they are the evidence for the branches that lost.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The short version: every bug found becomes an invariant in `test/run.sh`, and a design change belongs in `docs/design.md` with the measurement that decided it.

## Roadmap

**Implemented** — one milestone, `M1`, and its packages `P1`–`P8` are all landed: the boundary (`test/run.sh`), the hands' env and `bgrun`/`bgwait`, the turn with resume and the meter line, the system prompt, `/compact` with prefix stability, the demo run, independent review, and the reporter a block cannot shadow. `bash test/run.sh` checks every invariant in that list with no metered call; `runs/2026-10-26-demo/` holds the trajectory they were built for — twenty turns, one `Job:`, two truncations, one compaction, 83,724 prompt tokens, and `bash runs/2026-10-26-demo/check-prefix.sh` rebuilding all 20 requests from the record with 0 failed.

**Planned** — the milestone's acceptance is a person reading the trajectory and the harness, which is not something this repository can perform on itself. After that, what is deliberately absent is also decided: no tool-call protocol (that is the project), no sandbox, no tmux, no pty, no Python, no streaming in v0, no live output while a block runs.

The future this is aiming at: one primitive — a process in the background — carrying subagents, timers and reminders, with the harness small enough that a bug in it is a thing a reader can find. Whether the run is any good is the one judgement left to a reader.

## The demo run

[`runs/2026-10-26-demo/`](runs/2026-10-26-demo/) is one unattended run, committed as it happened: the trajectory, the meter, the requests, the workspace the agent left behind, and the command that regenerates all of it. `notes.md` points at the line each piece of evidence sits on, and says what the run cost to get.

## Not for

Anyone who wants a sandboxed, multi-user or networked agent service, a Python or TUI harness, or a tool-call protocol. Nothing is sandboxed on purpose: the harness sits outside everything the model can reach, and the model's hands are the shell state itself.

A block is bounded at 300 s (`AGENT_SH_BLOCK_TIMEOUT`), because a block that reads stdin would otherwise hang an unattended run forever; the price is the shell state it built, and the message says so. The wait for a background job is bounded too (`AGENT_SH_JOB_WAIT`, 600 s): a job that outlives it is reported as still running and left for a later turn instead of ending the run.

## Licence

AGPL-3.0-only. See [`LICENSE`](LICENSE).

Copyright (C) 2026 ZisIsNotZis.
