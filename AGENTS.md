# agent.sh

This is an agent whose model has no tools: what the model writes is executed by one long-lived bash and the output returns as a message, so the whole project is the boundary between that bash and the loop that calls the model.
This node owns the project — the roadmap, the split, the integration and the decisions taken at `decide` — and `docs/roadmap.md` is where that lives.
The one milestone is an unattended run whose trajectory is the proof; nothing here is called done by whoever produced it.

## 入口

How to start: read this file, then `docs/roadmap.md` — the milestone, its four terms, the package table with statuses, and the decisions taken under `decide` with the cost of each.
Then `README.md` if you are a stranger to it, and `docs/design.md` if you are about to change the design: every branch that lost is there with the measurement that killed it, and re-running `probes/` re-measures the claims in about a minute.
`bash test/run.sh` is the invariant check that costs nothing and needs no metered calls.

How to continue: take the next open package in `docs/roadmap.md` whose dependencies are landed, and write its status into that table in the same commit that lands it.
Messages to this project land in `inbox/`; a message from this project is written into the receiver's own `inbox/`, never kept here.
Nothing that changes acceptance, cost, scope or the delivered result is spoken before it is written down.

Where this departs from the workspace convention: the project is a single bash harness with no build step, so there is no test runner and no dependency file — `test/run.sh` is plain bash and must stay runnable with bash 5.1+, coreutils and `jq`.
`probes/` is not a test suite: `02-single-shell.sh` and the last line of `03-boundary-nonce.sh` are deliberately failing branches, kept as evidence for why the chosen design won.
The session directory `$PWD/.session/` is ignored by git and is the only place a run may write outside `runs/`.

What is not current: the `README.md` of commit `aeb66c9` described the project as "one bash script that owns a stock bash as its hands … three shell functions" — corrected in `5264304`, and history is not rewritten.
`docs/design.md` and `docs/brief-m1.md` carry the headers they had as messages (`kind: direction`, `from: root`); they are project documents now and the headers are provenance, not routing.

## The repository this directory is

- This directory is a git checkout of `https://github.com/ZisIsNotZis/agent.sh.git`, branch `main`.
  The workspace holds it the way it holds every other project: as a submodule (`agent.sh` in the workspace `.gitmodules`) pinned at a commit of that repository.
  Advancing that pin is the workspace's act, not this directory's, so a commit here does not move it.
- The first commit, `aeb66c9`, and its message were made by root_manager's hands, which created the repository, copied the tree and pushed.
  That was root_manager's error and it is recorded as one: **the first commit of a project belongs to the layer that answers for the project**, and at that moment this directory had no such layer.
  The commit is not rewritten and will not be; the corrections are follow-up commits, and the two that exist say in their messages what they corrected and why.
- Pushes are authorised as a standing grant from the person: push when something is landed, and never force-push.
  So `git push origin main` after a commit that stands is expected, not asked about.
