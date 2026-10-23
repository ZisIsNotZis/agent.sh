# agent.sh

An absolutely minimal but fully functional agent: one bash script that owns a stock bash as its hands, so the model can run commands, spawn subprocesses, spawn subagents, set timers and leave itself reminders.

**Not for** anyone who wants a sandboxed, multi-user or networked agent service, and not for anyone who wants a Python/TUI harness. The whole surface is three shell functions and two pipes.

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
