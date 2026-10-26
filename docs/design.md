kind:    direction
from:    root
spend:   person_attention, about 20 minutes; taste on the four questions at the end; no compute, no money, nothing irreversible
id:      none — first contact

# agent.sh — the design tree we walked, branch by branch

This is the whole record of one conversation, 2026-10-22. The goal is in his words, the settled design is at the top, then every branch we considered with what it cost and why it lost, then what is still open. Nothing has been dispatched and no manager exists yet; the settled design needs no reply, the four questions at the end do.

## The goal, as he stated it

> an absolute minimal but fully functional agent called "agent.sh" that relies on a bash, implemented fully in bash

> absolute minimal but fully functional, at least capable of supporting most thing, subagent, subprocess, todo (reminded periodically), timer... But if very complex or not elegant to implement, that can be negotiated

Two words carry the whole argument: **minimal** and **functional**. His own reading of minimal is not "fewest lines of code" but **smallest injection surface + cleanest dependency set** — a plugin that hooks something bash never offered is out; a common trick already implemented by someone is in. That reframing is what decided several branches below, and it is the metric to keep using.

The interaction shape he drew: user input and command output both arrive as `<|user|>`; everything the model writes arrives as `<|assistant|>` and is executed by one persistent bash; `bgrun` detaches a command and reports a pid and a log; `bgwait` blocks for any finished job; the trajectory is maintained in chat-ml form and resumed with `-s`.

## The settled design

1. **Two processes, one direction of control.** `agent.sh` is the outer bash: it owns the person's tty, the API call, truncation, the trajectory and the timer. It starts one child bash as the hands via `coproc … { exec setsid bash --norc --noprofile 2>&1; }`. The hands have no tty, no job control, and no way to speak to the person or the network.
2. **The outer is not a spectator.** It never parses shell output to find out what happened. Everything it knows about the hands arrives in a token the outer itself defined.
3. **Boundary is arithmetic, not a search.** Per block the hands evaluate the text with its output redirected to a fresh file (`eval -- "$__b" >"$raw" 2>&1`), then write one slip on the control pipe: `SENT <nonce> <exit> <bytes>\x02`. Payload never travels on the control channel. The outer blocks on `read -d $'\x02'`, then takes exactly `<bytes>` from the file.
4. **Block text is transported as data, never as shell input.** A quoted heredoc whose random delimiter is the block's nonce, read into `__b`, then `eval -- "$__b"`. An unterminated quote is a status 2, never a hang.
5. **Nonce per block, from `/dev/urandom`.** The effective delimiter is random and multi-byte, though `read -d` is one byte. A stray delimiter byte costs one loop iteration and is reassembled; only a token carrying that block's nonce ends it.
6. **One primitive: `bgrun`.** Subprocess, subagent, timer and todo are all `sleep`/commands in the background: `bgrun cmd…`, `bgrun agent.sh -r roles/worker.md msg…`, `bgrun -n 'check: rewrite parser' sleep 900`. Job state is on disk — `jobs/<id>/{cmd,log,status,note}` — never in memory, so it survives the hands shell dying.
7. **`bgwait` is `wait -n -p`** (bash ≥ 5.1), which returns the pid that finished and its status; exit 127 means nothing is pending. No polling inside the model's turn.
8. **Polling exists exactly once, outside the model's turn**, and only while jobs are pending: `read -t 0.1` on the tty plus a check of the job dir. With no jobs pending the outer blocks on a plain read and wakes zero times.
   As landed in the `--blocks` driver there is no tty to tick against, so the wait is the hands' own blocking `bgwait` and the count of waits is printed instead; the `read -t` tick is what returns once a person types (P3).
9. **Injection is `BASH_ENV`** — documented for non-interactive shells, not a plugin — holding `bgrun` and `bgwait` and nothing else. It is sourced by subagents' hands shells too, so it must stay stateless and idempotent.
10. **`setsid` on the hands** puts them in their own session with no controlling terminal, so the person's `Ctrl-C` reaches only the outer, which can steer or forward. Verify the process-group layout on the target machine rather than trusting the comment.
11. **Trajectory is chat-ml text, append-only.** No JSON in the hot path; resume is reading the file back. JSON exists only at the API boundary.
12. **Binary is refused, not encoded.** If the slip's byte count and the readable text disagree, or `iconv -f UTF-8 -t UTF-8` rejects the file, the block reports `[binary output, N bytes, not shown]`.

## The tree

### D1. Which process is the agent?

| branch | what it is | why it lost / won |
|---|---|---|
| `D1a` tmux, terminal-agent style | a persistent terminal emulator session the harness types into | Rejected immediately by him: too much. Also drags in a dependency and a screen model nobody needs. |
| `D1b` one shell — the harness *is* bash, its stdio hijacked to files, `eval` in the same shell | the harness saves the real tty fds with `exec {out}>&1 {inp}<&0`, redirects the whole shell to a capture file, evals, reads the file, truncates, restores | **He argued for this and it works on the happy path.** Built and measured: `cd` and variables persist, `exec 1>/dev/null` inside a block is recovered on restore, a block reading stdin gets `/dev/null`, truncation is clean. It is also *shorter* than `D1c` by about six lines, and its boundary is a function return rather than a marker in a stream. It lost on failure, not on elegance — see below. |
| `D1c` two shells — outer owns a child bash over two pipes | chosen | Survives the death of the hands shell; the harness is outside everything the model can reach. |

Why `D1b` lost, in order of haste:

- **`set -e` ends the session.** A block containing `set -euo pipefail` and any failing command kills the harness and swallows that block's output — measured, exit 1, nothing printed. Models write `set -e` as a reflex when they are being careful, so this is not an adversary, it is ordinary diligence. `exit`, `exec bash`, `kill $$` and an OOM do the same.
- **The saved tty fds live in the shell the block can inspect.** Printing `/proc/$$/fd` from a block showed `/tmp/…/cap`, `/dev/null` and the harness's own save slots. Accidental clobber is unlikely (bash allocates `{out}` above 10), but the juggling happens on the model's side of the fence.
- **Block globals persist into the harness.** `trap 'echo HAHA' INT` was still installed afterwards; so does `shopt`, `IFS`, `set -u`, `umask`, `CDPATH`. `cd` and `export` persisting is a feature — his phrase was "a feature not a bug" — but `trap` replacing the harness's Ctrl-C handler and `set -e` deciding whether the harness lives are the model reconfiguring the harness by accident.
- **The truncate dance hides a bug.** `: >file` truncates but leaves the fd's offset, so the next write lands at the old offset and leaves a NUL-filled hole. Reopening with `>` each block avoids it, but that is one line of discipline between you and corrupt output the model reads as real.

The decisive sentence, his: *"so it's more like a super complex maze/puzzle, technically challengable, but with things like set -e … it's so fragile … let alone things like sandbox, the harness logic itself is inside sandbox, it's trivial to break-through."* And the crux under it: **you cannot restart a shell from inside itself.** Everything above is downstream of that. `D1c` costs one `coproc`, one `setsid` and one token; `D1b` costs the session whenever a block does something ordinary.

The strongest form of `D1b` — single shell plus resume-from-trajectory — was considered and is defensible for a v0: a bad block kills the shell, `agent.sh -s <same>` re-reads the trajectory and continues, so death costs a restart. The residual is that `set -e` also eats the failing block's output, so the record claims a block whose result nobody saw, and you cannot tell "the command failed" from "the harness died mid-block". Not chosen.

Rejected without much time: `D1b` nested inside `D1c` (both mechanisms, no gain).

### D2. How does the harness learn a block ended?

| branch | what it is | verdict |
|---|---|---|
| `D2a` hook bash's lifecycle | PS1, `PROMPT_COMMAND`, `DEBUG` trap, `bash-preexec`-style plugin | Rejected. A non-interactive bash prints job notices only from its prompt cycle, so with no prompt there is nothing to hook; and a plugin is exactly what his "no niece dependency" rule forbids. |
| `D2b` grep a special unicode marker from outside | scan the output stream for a glyph | Rejected. Visible glyphs are output the model legitimately produces — our own transcript contains the markers — and a scan is a guess about where the boundary might be. |
| `D2c` side channel for the boundary | separate result fd the hands write when done | Rejected *as the boundary*, because two fds have no ordering: when the status arrives nothing tells you the payload is complete, so you drain until two consecutive timeouts and a write still in flight lands in the wrong block. He suspected this himself ("that's easy to out-of-sync") and was right. It returns as `D2f`, where the slip carries a size and the race disappears. |
| `D2d` one-byte terminator on the payload stream | `read -d $'\x01'` | Works until the payload contains the byte. Measured on `printf 'a\x01b\x01SENT 0\nc\n'`: delivered `a` with status 0 and the **next block inherited `c`** — silent mis-attribution, the exact corruption he feared. |
| `D2e` terminator plus per-block nonce | same stream, token `\x02SENT <nonce> <status>\x02`, tokens reassembled with the delimiter between them | Correct: byte-exact on payloads containing `\x01`, `\x02`, marker-shaped lines with a wrong nonce, no trailing newline, empty output; 150 lines counted true. Still runs with the payload on the control channel, so a `cat /dev/urandom` costs one iteration per 256 bytes and loses NULs silently. |
| `D2f` payload to a file, slip on the control pipe | `SENT <nonce> <exit> <bytes>\x02`, chunk = `head -c <bytes>` | **Chosen.** Boundary becomes arithmetic. Nothing in the payload can impersonate a slip, and the byte count is a free integrity check. |

Facts established along the way, each of which killed a worry rather than a branch:

- **`read` is delimiter-seeking, not "whatever is available".** A short read from a pipe does not end the call; it accumulates until the delimiter or EOF. So "how much do I send the model" is not a judgement call. (Only `-t`, `-n`, `-N` return partial data; `read -t 0.3` on a half line returns status 142 with the partial text, so a timed read is workable but is a different primitive.)
- **`read -d` takes one character**, the first of its argument — `-d "ab"` stops at `a`. The nonce is what makes the effective delimiter multi-byte and random; his instinct that a random secret per block would be enough is right.
- **`printf %q` cannot transport the block.** It emits `it\'s` outside any quoting context and bash rejects it: `eval: unexpected EOF while looking for matching '`. The heredoc with a nonce delimiter is the floor, not laziness — measured on a body containing a lone quote.
- **`0x00–0xFF` is not a hypothetical worth designing for, and it costs nothing to survive.** 512 bytes containing every byte value twice: slip says `bytes=512`, NULs counted as 2, boundary untouched. 60 MB of `/dev/urandom`: `status=0 bytes=60000000`, non-NUL `59766202` — the mismatch *is* the binary alarm, and you send `[binary, not shown]` instead of garbage.
- **A late background writer is pinned out of the chunk.** A block ran `{ sleep .6; echo LATE; } & echo foreground`: chunk pinned at 11 bytes, the file grew to 23 afterwards, and the late bytes were never attributed to any block. The slip's byte count is what makes this exact; `bgrun` redirects its jobs anyway, so this only appears with a hand-written `&`.
- **The control channel is unreachable by accident, reachable by digging.** A block printing `/proc/$$/fd` sees `0->pipe 1->raw 2->raw 3->pipe 10->pipe`, so a block that goes looking can find the control pipe. It still cannot forge a slip, because the nonce is generated after the block was read. Honest residual: discovery, not collision.

### D3. Feature surface and minimality

- **One primitive.** `bgrun` covers subprocess, subagent, timer and todo. A todo reminder is a background `sleep` carrying a `-n` note that rides the wake line. No second mechanism was added for timers.
- **Job state on disk, one small file per job.** Nothing to desync, and it survives the hands shell being killed, which is the whole point of `D1c`.
- **"Is polling elegant?"** He asked. Answer used: bash has no `select()`, so a timeout on `read` is the only primitive that can wait on two sources. The elegance is in confinement — polling appears in exactly one place, outside the model's turn, and only while jobs are pending. With no jobs pending, the outer blocks and polls nothing.
- **Rejected:** a status file per job *plus* an in-memory table (two homes); a `todo` file with its own scheduler (a second mechanism for what `sleep` already does).

### D4. Which language?

bash, and not because of line count. The metric is injection surface plus dependencies: the thing being driven *is* bash state, so `cd`, env, functions, `&`, `wait -n -p`, heredocs and `$?` are the feature set for free. In Python the same design needs a pty/pexpect layer *plus* an invented job table *plus* an `wait -n -p` equivalent — more code and more invented machinery than the ~30 lines here.

Where Python would have won is JSON and string handling, and that is exactly one place: the API body. Handled by keeping JSON out of the hot path (`D7`).

### D5. How do binary payload and JSON get along?

bash has **no** binary-to-escaped output mode. Measured:

| candidate | result |
|---|---|
| `cat -v` | `héllo — 中文 ✓` → `hM-CM-)llo M-bM-^@M-^T …` — destroys valid UTF-8. Never use it as a sanitiser. |
| `iconv -f UTF-8 -t UTF-8` | says *valid* for `a\0b\033[31m` — NUL and ESC are legal UTF-8, so this is not a binary test on its own. |
| `tr -d '[:print:][:space:]'` | flags valid UTF-8 (`héllo 中文` → 8 "non-printable" bytes). Useless. |
| `jq -Rs .` on a file | **works**: NUL → `\u0000`, ESC → `\u001b`, invalid UTF-8 → U+FFFD, 3 MB of `/dev/urandom` in 0.14 s, always valid JSON, never an error. Lossy on invalid UTF-8. |

Decisions: the detector is *NUL present, or `iconv` rejects the file*. Never route payload through a bash variable — `jq --arg s "$(cat file)"` silently drops NULs (bash warns "ignored null byte in input"), so always `jq -Rs . < file`. And **do not auto-escape**: 3 MB expanded to 7 MB of JSON, an entire context window spent on noise. `jq -Rs` stays in the toolbox for the rare case where raw text must reach the API; the trajectory is chat-ml text and needs no encoding at all.

### D6. How do `bgrun` and `bgwait` get into the hands?

`BASH_ENV` — documented for non-interactive shells, one exported file, verified to work under `coproc` + `setsid`: `type -t bgrun` → `function`, a job started in one block reaped by `wait -n -p` in a later block. The alternative — prelude lines written into the pipe — keeps the env file out of the picture but puts non-protocol text on the control stream. `BASH_ENV` chosen.

Known leak: a subagent's own hands shell also sources it. Keep the file stateless and idempotent.

### D7. Session state

Trajectory file is the state. One block = one assistant message, one chunk = one user message, both appended as text with the chat-ml markers. Resume re-reads the file. The outer additionally keeps `PWD` so a restarted hands shell lands where the last one was working.

### D8. The turn, as landed

- **Markers, and only three.** `<|assistant|>` then the block verbatim, `<|user|>` then one message, and a `<|meter|>` line after each turn. A meter line lives in the trajectory rather than beside it because the milestone asks for a meter line on every turn of the trajectory, and because the totals must survive a resume; resume skips it, so it is a record, not protocol.
- **Resume parses the trajectory itself**, so there is one home for the conversation. The parser reads NUL-separated `(role, content)` pairs out of the file, which is safe exactly because binary output is refused — a NUL can never reach a recorded body. No second store, no index, no JSONL sidecar.
- **JSON lives only at the request boundary**, built by `jq` from the trajectory and the prompt file and parsed by `jq` back: the record stays text, and `jq` is a dependency the workspace already allows. Each turn's request is kept as `req.<n>.json` beside its response, because a claim about prefix stability should be checkable against what was actually sent, not against the code that built it.
- **`--stub` is the model-in-a-file for the turn**, the same idea the blocks driver already uses: a script that reads the request and writes a response. Every invariant of the loop, the meter and resume is checked with it for free, and `complete()` is the one function where a network call can happen.
- **A block is bounded by the wall clock** (`AGENT_SH_BLOCK_TIMEOUT`, 300 s by default). An unattended run that hangs is the one failure that produces no evidence at all, and the only thing the harness can do about a block reading stdin is to kill its hands — which costs the shell state, and saying so in the message is truthful. Measured: the first demo attempt died on a block waiting for input, so the bound was added rather than a promise in the prompt.
- **The reply is executed raw.** No fence stripping, no `$ ` trimming, no prose detection: the design says the model's text *is* the block, so a model that writes prose gets prose executed and learns from the error — which is the experiment.

### D9. Compaction, as landed

`/compact` is not a rewrite and not a second store: it **appends** `User: /compact`, then a record `<|compact|> kept=<n>` and `<|summary|> …`, and every later request is *rebuilt* as system + the summary as one user message + the messages after `kept`.
That keeps the one property everything else rests on: the file only grows, so a resumed run never re-reads a byte it has already seen.

- **The summarisation call is a prefix extension**, exactly as it is in pi: the last user message is the `/compact` command plus the instruction, so the provider finds the whole conversation inside that request and it is a cache hit, not a cold start.
- **The boundary is exempt from the cache rule, once.** The request after a boundary is a freshly built prefix, so `check-prefix.sh` skips exactly that one; the compaction call itself is still checked, because it extends the old prefix.
- **The trigger is a token count, not a context overflow**: `--compact-at N` compacts when the last turn's `prompt_tokens` reached `N`. That is also how a demo can show compaction at 8k for pennies instead of waiting for a real window to fill.
- **A request whose previous prompt is at or under one 1024-token chunk is reported as unverifiable**, not as passed: the arithmetic of "the prefix was found" needs a prefix larger than the smallest chunk the provider counts in.

## What is still open

1. **Wake policy mid-turn.** Answered in `docs/roadmap.md` under `decide`, with its cost: a finished job ends the turn and arrives as its own `Job:` message.
2. **Does the outer poll ship in v0 at all?** Answered there too: it ships, as `drain`, counted on the epilogue line.
3. **Truncation window and the `[status N]` line.** Answered there: `--lines N`, default 100, and the status of every block including a comment-only one.
4. **Degree for this project.** Closed by `inbox/2026-10-22-manager-brief.md`: it runs at `decide`, because he wants to see how good an agent is without his supervising. The register carries `level: decide` and `model_work: deepseek-flash`; the first three questions above are now the manager's to answer, not his.

Also unsettled, manager-sized rather than person-sized: the content of the role files (`root`/`manager`/`researcher`/`worker`/`reviewer`), the recursion budget for `bgrun agent.sh`, and whether a subagent's trajectory lives under the session dir or under a directory per child.

## Non-goals, so scope stays bounded

No tmux. No bash plugin. No Python. No pty. No live streaming of a block's output to the person (capture, truncate, then show). No binary content to the model. No sandbox — the harness is deliberately *outside* everything the model can reach, which is the opposite of sandboxing the harness. No second mechanism for timers, todos or status.

## Evidence

`probes/` holds the runnable form of every measurement above; `probes/README.md` says what each proves and what a healthy run prints.

- `probes/01-read-semantics.sh` — `read` accumulates; `-d` is one byte; `read -t` partial + 142; `%q` broken; bash job control silent; `wait -n -p` returns completion order and 127 when empty.
- `probes/02-single-shell.sh` — the `D1b` prototype: happy path passes, then `set -e` ends the harness (the last line does not print).
- `probes/03-boundary-nonce.sh` — `D2e`: nonce token on the payload stream, byte-exact through delimiters, marker-shaped lines, missing trailing newline.
- `probes/04-control-slip.sh` — `D2f`, the chosen design: binary alarm by byte count, 8 MB payload, late background writer pinned out, `exec 1>&2` recovered, 150-line truncation.
- `probes/05-payload-safety.sh` — `cat -v` mangling UTF-8, `iconv` and `tr` failing as binary tests, `jq -Rs` escaping NUL from a file, the `--arg` NUL loss.

## effort

Chosen: `D1c` + `D2f` + nonce + `BASH_ENV` + `bgrun`/`bgwait` + chat-ml text trajectory. Closed because measured, not argued: `D1b` (set -e, fd namespace, globals), `D2a` (no prompt in a non-interactive shell), `D2b` (glyphs are legitimate output), `D2c` as a boundary (no ordering), `D2d` (splits on binary), `%q` (invalid for a lone quote), `cat -v` (mangles UTF-8), `tr`/`iconv`-alone as binary tests.

Would reopen: a bash ≥ 5.1 that is unavailable on the target (kills `wait -n -p`, `bgwait` becomes `kill -0` polling); a person who wants live output while a block runs (payload back on a stream, boundary back to `D2e`); a model that cannot be trusted not to `set -e` — no, that one is not a reason to reopen `D1b`, it is the reason it lost.
