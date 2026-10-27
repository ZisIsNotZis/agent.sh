# Contributing

## Scope

The project is one bash harness and the boundary it defends: a block of the model's text in, the block's own status and byte-exact output out. What is in scope is a bug in that boundary or in the loop around it; what is out of scope is named on purpose in [`docs/roadmap.md`](docs/roadmap.md) under "Not doing" — no tool-call protocol, no sandbox, no tmux, no pty, no Python, no streaming in v0. Read that list before proposing a feature: an omission there is a decision, not an oversight.

The declared residuals are in [`docs/design.md`](docs/design.md) D10 and D11. A report that reproduces one of them is useful as a reproduction; it is not a new finding.

## How to check your work

There is no build step and no dependency file. `test/run.sh` is plain bash and must stay runnable with bash 5.1+, coreutils, `iconv` and `jq`:

```sh
bash test/run.sh                             # every invariant, no API call, exit 0 means they hold
bash agent.sh --blocks examples/tour.sh       # a free run; read .session/<stamp>-<pid>/traj.md
bash runs/2026-10-26-demo/check-prefix.sh     # rebuilds a committed run's requests from its record
for p in probes/*.sh; do bash "$p"; done      # re-measures the claims the design rests on
```

Two probes fail on purpose (`02-single-shell.sh`, and the last line of `03-boundary-nonce.sh`): they are the evidence for the branches that lost.

Nothing here is metered, and a change that needs `DEEPSEEK_API_KEY` to be checked is a change that has not been checked.

## What a pull request is expected to carry

- **The failure first.** A bug report is a reproduction — the block, the command, what came back, what should have come back. If it cannot be reproduced, it is a question, not a bug.
- **A test for the fix.** Every defect found so far became an invariant in `test/run.sh`, including the six that were introduced by the fix for the one before. A fix without one is half a change.
- **The document the fact belongs to.** A design change goes into `docs/design.md` with the branch it beat and the measurement that decided it; a package status goes into `docs/roadmap.md` in the same commit that lands it. Prose that only lives in a commit message is lost at the next compaction.
- **Small commits**, in Conventional Commit form, each standing on its own.

No contributor licence agreement: contributions land under AGPL-3.0-only, the licence in [`LICENSE`](LICENSE).

## Issues

Bring the reproduction, the version of bash (`bash --version`), and the platform if the boundary is involved, since `wait -n -p` and `coproc` are where a platform difference shows. Say what you expected as a fact about the harness, not as a preference about the design — the design's branches are recorded with their costs and can be argued with, but only by beating that record.
