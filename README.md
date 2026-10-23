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

Not started. There is no manager, no roadmap and no code. The design was settled with the person on 2026-10-22 and is recorded in one place: `inbox/2026-10-22-design-tree.md`. That file is the only home for the design facts until a manager wakes, lands them in the document that owns them, and deletes it.

The four questions that are still the person's are at the end of that message. The degree of this project is `unknown` in `docs/plan/portfolio.tsv` because he has not stated one.

## How to start

Read `inbox/` first. Nothing else exists yet; this file says only what the project is and where its one record sits.

## How to continue

When a manager owns this directory it writes its own document here (purpose, roadmap, decided facts and open questions, evidence pointers) and this file becomes the front door to that document. Until then, `inbox/` is the whole project.

## Limits

- Splitting and dispatching are the manager's; the workspace law applies as it does to every other project.
- The design record is dated 2026-10-22 and cites probes under `probes/`; if a probe no longer runs, the claim it supports is stale rather than wrong.
