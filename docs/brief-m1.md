kind:    direction
from:    root
spend:   person_attention, about 12 minutes; taste: none — the person has delegated the deciding; machine_time, idle class; money: metered on the person's `DEEPSEEK_API_KEY`, on the order of a few hundred thousand prompt tokens for the demo run, no device held
id:      none — first contact; the design record it builds on is `docs/design.md`

# The order: build the thing, decide everything yourself, prove it with a trajectory

The person's own framing, which sets the degree: *"I'm trying to see how good can an agent do without my supervising."* So this project runs at **`decide`** — you take the decisions he would otherwise take, record them as `assumed`, and disclose them at the milestone instead of asking. Only two things are his: the one milestone, and whether the result impresses him.

Nothing here is one of your contract's six lines. Your dispatch contract arrives with the six, and it will point at this file rather than repeat it.

## The milestone: exactly one, and it is the end product

**One milestone. The end product, working, with the trajectory as the proof.** No intermediate gates, no "core first" milestone. Everything below the milestone is yours to split.

The person's words on what the end product is:

> a working agent (test and see trajectory), it should understand it's living in a different kind of harness than regular tool-based, that it got no tool and it's output is connected to bash directly, use comment/echo to talk to user. It should have a clear way to differentiate user message and bash output, like `User:`. bgrun and bgwait shall work. async message arrival better work. You should explain those functions to agent otherwise agent don't know (because it's not in tool list). Handy functions like even without bgrun, if output more than 100 lines, truncate that to a /tmp file and tell model it's truncated, total num lines, only showing the last 100 thing. For other details you can think carefully, system prompt (i.e. root markdown)/role prompt can be copied from our existing ones, harness overhead (like bgrun/bgwait) shall be minimal... /compact should work, and the whole harness shall be designed perfect prefix-matching (never change prefix), even when generating compact (that command is an appended message), you can refer to other harness like pi to see how its done.

And the two constraints on the run: **completions API for now; `deepseek-flash` at thinking level `low`, `$DEEPSEEK_API_KEY` already in the env.** He expects to be impressed, which in practice means: the demo shows the thing doing something he could not have done with a copy-paste prompt, and the trajectory shows it happening without a tool list.

## Before you roadmap: review the design, then think

Read the design record first. It carries the settled leaf, every branch we walked, and why the losing ones lost. The reason it matters is that several of its facts are counter-intuitive and you will otherwise re-walk them: bash job control never notifies a non-interactive shell; `printf %q` cannot transport a block; `cat -v` mangles UTF-8; `read -d` is one byte. `probes/` re-measures each one in about a minute.

The person's instruction is to review that design "with minimal in mind" before drawing the roadmap. Minimal here is the metric he defined, not a style: **smallest injection surface and cleanest dependencies**, not fewest lines. A decision that adds a dependency loses even when it saves code; a decision that adds a hook inside bash loses even when it is elegant.

## Facts root already established, so you do not rediscover them

Measured on this machine today; re-running each is one command.

1. **The API works and this is the shape of it.**
   `POST https://api.deepseek.com/chat/completions` with `Authorization: Bearer $DEEPSEEK_API_KEY`, body `{"model":"deepseek-flash","reasoning_effort":"low","messages":[…],"max_tokens":N}` → 200. `GET https://api.deepseek.com/models` confirms `deepseek-flash` (DeepSeek-V4.1-Flash, 1048576 context, 393216 max output, `effort.supported_levels: [low, high, max]`). `reasoning_effort: "low"` is accepted as a plain top-level field. Note that `~/.pi/agent/deepseek-config.json` says `apiFormat: openai-responses`, so pi talks to it differently — chat completions is nonetheless live, and the person said "completions for now".
2. **The response carries the evidence for prefix matching.** `usage.prompt_cache_hit_tokens` and `usage.prompt_cache_miss_tokens`. Measured: a 1242-token prompt repeated with one extra message appended returned `prompt_cache_hit_tokens: 1024`, `miss: 227`. So the acceptance test for "never change the prefix" is not a code review, it is arithmetic: **on turn *n*+1, `prompt_cache_hit_tokens` should be roughly `prompt_tokens` minus the newly appended tail.** It is chunked (1024 of 1242), so compare with a margin, not for equality. Print both numbers every turn and keep a cumulative line; that is your proof and it costs nothing.
3. **pi's compaction is an append-only log plus a rebuild, not a rewrite.** `docs/compaction.md` in pi: the session is a log of entries; compaction **appends** a `CompactionEntry` carrying `{summary, firstKeptEntryId}`, the raw entries stay on disk, and the context for the next request is *rebuilt* as `system + summary + everything from firstKeptEntryId onwards`. Repeated compactions summarize from the previous boundary, passing the old summary in as iterative context. That is why "never change the prefix" and "/compact" coexist: the log only grows, and the request prefix changes exactly once per compaction and is stable again after. And because `/compact` is itself appended as a user message, the summarization request is a prefix *extension* of the conversation, so it reuses the cache rather than starting cold. Copy that shape; do not invent a second one.
4. **The role files to copy from** are `agent-policy/agents/{manager,researcher,worker,reviewer,policy_worker}.md` (symlinked into `~/.pi/agent/agents/`). The root view is not a file — it is rendered by `python3 agent-policy/tools/build.py` (`ok: 6 views`, `root 328 nodes`); `python3 agent-policy/tools/law.py --help` shows how to print one view. Taking the root view as your system prompt is the obvious move, but it is ~330 nodes and the person asked for minimal, so consider whether a role file plus a short harness section beats it.
5. **Two neighbour references worth ten minutes.** `~/.pi/agent/npm/node_modules/pi-bg-bash/README.md` is the shape bgrun/bgwait are aiming at, including "when it exits the agent receives one message with the exit state and the last lines of output, which starts a turn if it was idle" — that is exactly the async-arrival requirement. `pi-cache-optimizer/README.md` says what pi does to keep prefixes stable: stable content at the front, volatile content never at the front; note that pi stopped lifting content because Pi orders its sections stable-to-variable already.
6. **The runtime kills a child at 30 minutes** and a killed child writes no report. Plan the wall clock inside that, as the workspace's own first run learned the hard way.

## Proposals root has already thought through — all overrulable

Marked as proposals because the deciding is yours; each is cheap and each was already weighed.

- **`#` versus `echo`, asked directly, and the answer is both.** Neither needs harness support: the whole assistant block is already displayed verbatim to the person, so a comment narrates for free and `echo` costs bytes it then repeats in the output. Recommendation: `#` for narration and reasoning, `echo` when the text must land in the recorded output (a checklist that later output refers to). Enforce nothing — a parser here would be harness logic that buys nothing.
- **Labels for the user role.** One prefix per message and nothing else: `User: ` for the person, `Bash: ` for a block's output, `Job: ` for a background completion. Three labels, written into the system prompt, and the trajectory keeps them so a resumed session is faithful. The `[status N]` line belongs inside the `Bash:` message, not beside it.
- **Truncation, and why it is almost free.** The design already writes every block's full output to a file before the model sees anything; that file *is* the overflow file. So add `lines=N` to the control slip and emit `[truncated: total 1234 lines, showing last 100; full output at <path>]` in front of the tail. Use the session directory rather than `/tmp`: same accessibility, survives a reboot, and the model can page it with `sed -n '1,50p' <path>` — which is the no-tools equivalent of a read tool, and worth saying in the prompt.
- **No streaming in v0.** Non-streaming is one request and one block; streaming is decoration until the loop is proven. Keep it behind a flag if you like.
- **Volatile content never in the prefix.** System prompt, role, tool/function documentation and the protocol text are the stable front. The date, `pwd`, the todo remainder, the last job status and the turn counter are volatile and belong in the newest `User:`/`Bash:` message. This is the rule that makes point 2 above true; getting it wrong is the only way to have a "perfect prefix" design that still misses.
- **Demonstrate compaction cheaply.** Do not wait for a real context to fill: a `--compact-at <tokens>` flag (default a slice of the window) lets the demo compact at 8k and show the before/after prompt reconstruction and the cache numbers across it, for pennies.
- **The harness prints its own meter.** One line per turn with cumulative prompt tokens, cache hit/miss and the money-equivalent if the API returns one. It is the milestone's evidence and it keeps the person's key honest.

## What is yours, and not root's

The package split, the file layout, the prompt text, the exact protocol bytes, the truncation wording, the demo scenario, how you verify it, whether the harness is one file or three, and whether any of the proposals above survive contact with the design. Root dispatches the review of your milestone; root does not plan inside this directory.

## What bounds you

- One milestone; a package is not a milestone and a milestone is not split into "core" and "polish".
- Commit inside `agent.sh/` at each cohesive step; do not push; touch nothing outside this directory.
- Every claim in your report needs the command that shows it. The milestone's proof is a real trajectory file from a real run, plus the cache line, not a description of one.
- At the terminator, report once with three fields — whose roadmap changes, the evidence pointer, the decision needed — and return. Under `decide` the decision is usually `none` because you already took it.

## Evidence

- `docs/design.md` — the settled design, the branches, the four questions it left open, and which of them are now yours to answer.
- `probes/` — five runnable measurements; `probes/README.md` says what each proves.
- The API facts above were measured today with `curl` against `api.deepseek.com`; the cache numbers came from two requests sharing a 1242-token prefix.
- pi's compact mechanism: `docs/compaction.md` in the installed pi package, sections "How It Works" and the before/after diagrams.
