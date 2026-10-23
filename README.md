# agent.sh

An agent that is given no tools.
What the model writes is not searched for tool calls: it is handed to one long-lived bash and executed, and what that bash printed comes back to the model as the next message.
The harness is the outer bash — it owns the API call, the trajectory, the labels and the truncation — and its hands are a `setsid bash` with no tty, reached over a `coproc`.
Two pipes carry only control: block text in, and a slip carrying `{nonce, exit status, byte count}` out, while the output itself sits in a file the outer reads by byte count.
That arithmetic boundary is the one idea here, and the project exists to see how far an agent gets with nothing else.
The deliverable is a trajectory from a real unsupervised run, not a feature list.

**Not for** anyone who wants a sandboxed, multi-user or networked agent service, or a Python/TUI harness.
Nothing is sandboxed on purpose: the harness sits outside everything the model can reach, and the model's hands are the shell state itself — `cd`, env, `&`, `wait -n -p`.
Two shell functions are injected through `BASH_ENV` (`bgrun`, `bgwait`) and nothing else is.

## Status

Owned by a manager since 2026-10-23; the roadmap is `docs/roadmap.md` and one milestone is running.
No code, no licence and no runnable example yet — the roadmap names each as a package or a limit.
The design was settled with the person on 2026-10-22 and lives in `docs/design.md`.

## How to start

Read `AGENTS.md` for what this directory is and how it is held, then `docs/roadmap.md` for what is being built and what checks it off.
`docs/design.md` is the record of the design and of every branch that lost, with the measurement that killed it.

## How to continue

Take the next open package in `docs/roadmap.md` whose dependencies are landed, and write its status back into that table in the same change that lands it.
Messages to this project land in `inbox/`; the roadmap owns the milestone, so nothing else may hold it.

## Limits

- Splitting and dispatching are the manager's; the workspace law applies as it does to every other project.
- The design record is dated 2026-10-22 and cites probes under `probes/`; if a probe no longer runs, the claim it supports is stale rather than wrong.
