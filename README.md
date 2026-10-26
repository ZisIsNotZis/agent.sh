# agent.sh

[![licence: AGPL-3.0](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)

**An agent with no tools.** The model is never asked to produce a tool call: whatever it writes is handed to one long-lived bash and executed, and what that bash printed comes back to it as the next message. Two shell functions are injected; nothing else is.

The harness is the outer bash — it owns the API call, the trajectory, the labels, the truncation — and its hands are a `setsid bash` with no tty, reached over a `coproc`.

```sh
git clone https://github.com/ZisIsNotZis/agent.sh
cd agent.sh
bash test/run.sh                                   # every invariant, no API call, under two seconds
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

Running. The loop is closed and honest about what it has proven:

- landed: the boundary (nonce slip, byte count, arithmetic), truncation with the raw file named, binary refusal, the harness surviving a block that kills its hands, `bgrun`/`bgwait` over disk job state, a job outliving the model's turn and arriving as `Job:` with its note, the turn itself — completions call, reply executed as the block, meter line, resume that only ever appends — and a system prompt that teaches the protocol, since there is no tool list to teach it.
- next: `/compact` as an appended message plus a rebuilt prompt, then one real unattended run committed under `runs/<date>-demo/`, then review by someone who did not write it.

`bash test/run.sh` checks all of that with a stub model, free and deterministic — 39 invariants, including the one that matters most: `test/check-prefix.sh` reads a run's own `usage` lines and fails if the prompt cache stopped matching, so "the prefix never changes" is arithmetic rather than a promise. The live path is one thin `curl` behind it.

The milestone, its four terms, the not-doing list and every decision taken with its cost are in [`docs/roadmap.md`](docs/roadmap.md). Whether the run is any good is the one judgement left to a reader.

## The demo run

[`runs/2026-10-26-demo/`](runs/2026-10-26-demo/) is one unattended run, committed as it happened: the trajectory, the meter, the requests, the workspace the agent left behind, and the command that regenerates all of it. Seventeen turns, one background job, one truncation, two compactions, 86k prompt tokens, and — the part that matters — `bash check-prefix.sh` finds every prefix intact across it. `notes.md` points at the line each piece of evidence sits on, and says what the run cost to get.

## Design, and what it cost

[`docs/design.md`](docs/design.md) records the settled design and every branch that lost, with the measurement that killed it; [`probes/`](probes/) re-runs those measurements in about a minute, including the two that are supposed to fail.

```sh
for p in probes/*.sh; do bash "$p"; done
```

## Not for

Anyone who wants a sandboxed, multi-user or networked agent service, a Python or TUI harness, or a tool-call protocol. Nothing is sandboxed on purpose: the harness sits outside everything the model can reach, and the model's hands are the shell state itself.

Requirements: bash 5.1+, coreutils, `iconv`, `jq`, and `curl` for the live path. No dependency file, no build step — `test/run.sh` is plain bash.

A block is bounded at 300 s (`AGENT_SH_BLOCK_TIMEOUT`), because a block that reads stdin would otherwise hang an unattended run forever; the price is the shell state it built, and the message says so.

## Licence

AGPL-3.0-only. See [`LICENSE`](LICENSE).

Copyright (C) 2026 ZisIsNotZis.
