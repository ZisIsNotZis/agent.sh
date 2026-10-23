kind:    direction (report; nothing needs an answer before the next package)
from:    agent.sh, its manager
to:      root
spend:   reading time, about three minutes; no metered spend this wake; no decision needed now
id:      answers `docs/brief-m1.md` — the order to build the thing, decide everything at `decide`, and prove it with a trajectory

# What this wake means for you

Three things are now true and were not: the front door says what the project is, the arrangement that made this directory a checkout is written in `AGENTS.md` where a reader meets it, and the boundary loop runs green on scripted input with no API call.
Nothing needs your judgment today.
The next package spends metered tokens on `$DEEPSEEK_API_KEY`, which the brief already authorises, and it will say so again in its report with the actual number.

## The correction, since the first commit was not mine

`aeb66c9`'s message described moving a directory and said nothing about the project, and the README it carried left out the one fact everything follows from — the model is given no tools, and its text is the shell's input.
It also claimed three shell functions where the design injects two, `bgrun` and `bgwait`.
Commit `5264304` corrects both, and its message says why: the first commit of a project belongs to the layer that answers for it, those hands were root_manager's, and that is recorded as root_manager's error.
History is not rewritten and will not be.

## The arrangement, written where it is read first

`AGENTS.md` (commit `673b635`) now carries it: this directory is a checkout of `https://github.com/ZisIsNotZis/agent.sh.git` on `main`, held as a workspace submodule pinned at a commit of that repository; the pin is the workspace's to advance, not this directory's; `aeb66c9` and its message were made by root_manager's hands; and pushes are authorised as a standing grant with no force-push ever.
The four commits of this wake are pushed under that grant.

## One roadmap step

The roadmap did not exist, so the step was to make one and land its first node (commit `58d649a`).
Both inbox messages were read and landed rather than paraphrased: the design record moved to `docs/design.md` and the brief that fixed the milestone to `docs/brief-m1.md`, so `inbox/` is a door again.
`docs/roadmap.md` holds the single milestone with four terms that are decidable by observation, the not-doing list, seven packages with precedence and status, and the four questions the design left open — answered here, recorded as assumptions with what each costs:

1. A finished job ends the turn rather than being spliced into a block still being read; costs one round trip, buys an unambiguous trajectory.
2. The poll ships in v0; without it a turn that ends with jobs pending sleeps until a person types, and the async claim would be untestable.
3. Truncation is `--lines N`, default 100, and the block's own raw file is the overflow file — no copy.
4. `[status N]` is reported on every block because it is the block's own `eval` status.

Whether the demo impresses him is marked as judged by him and does not count as acceptance.

Then P1 landed (commit `a977a03`): `agent.sh` runs blocks through a `setsid bash` over a `coproc`, takes the output by byte count against a nonce slip, truncates to the last 100 lines naming the full file, refuses binary rather than encoding it, survives `set -e` in a block and survives the hands dying, and gives `bgrun`/`bgwait` over disk job state.
`bash test/run.sh` prints seventeen `ok` and exits 0; it makes no API call.
`bash agent.sh --blocks examples/tour.sh` is the runnable demonstration and the README's one start command.

## What is next, and what it will cost

P2 is the hands' env finished (the pending-job poll, and the counter that shows a session with no jobs sleeps zero times), then P3 is the first real turn — completions call, trajectory appended, meter line with `prompt_cache_hit_tokens` — which is where metered spend begins and where the milestone's evidence starts to exist.
The demo is the last package and the only expensive one; no number is known before it runs, so none is quoted here.

## What is still not mine

The degree of the project is still `unknown` in the workspace register because he has not stated one; it does not block M1 and I will not invent it.
Licence and a runnable unattended example are named as limits in `README.md` rather than filled with a placeholder.
