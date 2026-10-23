#!/usr/bin/env bash
# test/run.sh — the invariants of the boundary that cost nothing to check.
# No API call, no metered anything: every block is scripted text. Exit 0 means they hold.
set -u
cd "$(dirname "$0")/.." || exit 1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

out=$work/out.txt
cat >"$work/blocks.sh" <<'BLOCKS'
echo hello; echo world
%%
false
%%
set -e; false; echo unreachable
%%
echo still-alive-after-set-e
%%
for i in $(seq 1 150); do echo line$i; done
%%
head -c 200 /dev/urandom
%%
printf 'SENT deadbeef 0 0\002\n'; printf 'a\001b\002c\n'
%%
echo clean-after-marker
%%
bgrun sh -c 'echo job-hi; exit 4'
%%
bgwait
%%
cat "$AGENT_SH_JOBS"/1/log
%%
exit 7
%%
echo alive-after-the-hands-died
BLOCKS

AGENT_SH_SESSION_ROOT=$work/session bash agent.sh --blocks "$work/blocks.sh" >"$out" 2>"$work/err.txt"
rc=$?

fail=0
has()  { if grep -qF -- "$1" "$out"; then printf 'ok   %s\n' "$2"; else printf 'FAIL %s  (no %q in the output)\n' "$2" "$1"; fail=1; fi; }
hasnt(){ if grep -qF -- "$1" "$out"; then printf 'FAIL %s  (found %q, and it must not be there)\n' "$2" "$1"; fail=1; else printf 'ok   %s\n' "$2"; fi; }

((rc == 0)) && printf 'ok   agent.sh exits 0\n' || { printf 'FAIL agent.sh exited %s\n' "$rc"; fail=1; }

has 'Bash: hello'                        'a block comes back labelled and executed'
has 'world'                              'the whole block, not only its first line'
has '[status 0]'                         'the status line rides inside the message'
has '[status 1]'                         'a failing block reports its own status'
has 'still-alive-after-set-e'            'set -e in a block does not take the harness with it'
hasnt 'unreachable'                      'set -e still stops that block where it should'
has '[truncated: total 150 lines, showing last 100' 'a long block is truncated with the count'
has 'line150'                            'the truncated view is the tail, not the head'
hasnt 'line1 '                           'the head of a long block is not shown'
has '[binary output, 200 bytes, not shown]' 'binary output is refused, not encoded'
has 'clean-after-marker'                 'a payload shaped like a slip does not desync the boundary'
has '[status 4]'                         'bgwait reports the exit status of the job it reaped'
has 'job-hi'                             "a job's log is readable in a later block"
has '[the hands exited during this block' 'the harness survives the hands dying'
has 'alive-after-the-hands-died'         'a fresh bash serves the next block after a death'

# the trajectory is the resume record, so it must carry both sides of every block
traj=$(find "$work/session" -name traj.md -size +0 | head -1)
if [[ -n $traj ]] && grep -qF '<|assistant|>' "$traj" && grep -qF '<|user|>' "$traj"; then
  printf 'ok   the trajectory records both sides of each block\n'
else
  printf 'FAIL the trajectory is missing or one-sided\n'; fail=1
fi

((fail == 0)) && printf '\nall invariants hold\n' || printf '\nsomething above failed\n'
exit "$fail"
