# probes/ — every measurement the design rests on, in runnable form

These are not tests of `agent.sh`; `test/run.sh` is. Each one is the experiment that decided a branch of the design tree, kept so a claim in `docs/design.md` can be re-run instead of believed. A probe that no longer prints its expected lines makes the claim it supports stale, not wrong.

Run them from the project root. They are short, they use `mktemp -d`, and they need only bash 5.1+, coreutils, and `jq` for the last one.

| probe | branch it decides | a healthy run looks like |
|---|---|---|
| `01-read-semantics.sh` | the primitive under every boundary choice | every line `EXPECTED`; `-d "ab"` stops at `a`; `wait -n -p` names the child that finished and returns 127 when none is pending |
| `02-single-shell.sh` | `D1b`, one shell that hijacks its own stdio | the state lines print, then `set -e` ends the harness — **`UNREACHABLE` must not print** and the exit status is non-zero |
| `03-boundary-nonce.sh` | `D2e`, payload and boundary on one stream with a per-block nonce | every case `BYTE-EXACT`, including a payload containing `\x01` and `\x02` and a marker-shaped line with a wrong nonce; the last line shows `D2d` splitting the same payload |
| `04-control-slip.sh` | `D2f`, the chosen design | `plain` 2 lines; `everybyte` 512 bytes with `nul_bytes=2`; the late writer's file grows while the chunk stays pinned; `following` is clean; `lines150` shows 100 of 150 |
| `05-payload-safety.sh` | `D5`, binary and JSON | `cat -v` mangles UTF-8, `iconv` accepts NUL and ESC, `jq -Rs` escapes them from a file, and `--arg` drops the NUL |

Two of them are deliberately negative: `02` demonstrates a shell dying, and the last line of `03` demonstrates the bug the nonce was introduced to remove. Read them as evidence about the losing branches, not as failures.

`04` writes an 8 MB `/dev/urandom` file and takes a few seconds; `05` writes 3 MB and takes under a second.
