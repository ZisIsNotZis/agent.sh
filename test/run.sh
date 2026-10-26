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

# the wake: the file has stopped writing, one job is still running, and that job gets a turn
cat >"$work/wake.sh" <<'BLOCKS'
bgrun -n 'a slow build' sh -c 'sleep 0.4; echo built'
%%
echo the model keeps writing while the job runs
BLOCKS
AGENT_SH_SESSION_ROOT=$work/wake bash agent.sh --blocks "$work/wake.sh" \
  >"$work/wake.out" 2>"$work/wake.err"

hasin(){ if grep -qF -- "$2" "$1"; then printf 'ok   %s\n' "$3"; else printf 'FAIL %s  (no %q in %s)\n' "$3" "$2" "$1"; fail=1; fi; }
hasntin(){ if grep -qF -- "$2" "$1"; then printf 'FAIL %s  (found %q in %s)\n' "$3" "$2" "$1"; fail=1; else printf 'ok   %s\n' "$3"; fi; }

hasin "$work/wake.out" 'Job: job 1 exited 0 — note: a slow build' \
  'a job left running gets a Job: turn of its own, carrying its note'
hasin "$work/wake.out" 'Bash: the model keeps writing while the job runs' \
  'the model kept writing in between'
hasntin "$work/wake.out" 'Bash: job 1 exited' \
  'the wake is labelled Job:, never Bash:'
hasin "$work/wake.err" '2 blocks, 1 polls' 'one wait for one pending job'
hasin "$work/err.txt" 'blocks, 0 polls' 'a session that ends with no job pending sleeps zero times'

wake_traj=$(find "$work/wake" -name traj.md -size +0 | head -1)
hasin "$wake_traj" 'Job: job 1 exited 0' 'the wake is recorded in the trajectory too'

# the turn: a model in a file, so the loop, the meter and resume are all free to check
wake_stub=test/stub-model.sh
s1=$work/turn
bash agent.sh --task 'say hello and start a job' --session "$s1" --stub "$wake_stub" --max-turns 2 \
  >"$work/turn.out" 2>"$work/turn.err"
hasin "$work/turn.out" 'Bash: hello from turn one' 'a turn runs its reply as the block'
hasin "$work/turn.out" 'Job: job 1 exited 0' 'a job finishing between turns arrives as Job:'
hasin "$s1/traj.md" '<|meter|> turn=1 prompt=1200' 'the trajectory carries a meter line per turn'
hasin "$s1/traj.md" '<|meter|> turn=2' 'one meter line for each turn, in order'
hasin "$work/turn.err" 'cumulative prompt 3600' 'the meter totals across the session'

# resume: killed after one turn, continued, and the record only grew
s2=$work/resume
bash agent.sh --task 'go' --session "$s2" --stub "$wake_stub" --max-turns 1 >/dev/null 2>&1
cp "$s2/traj.md" "$work/after-one.md"
bash agent.sh --session "$s2" --resume --stub "$wake_stub" --max-turns 2 >/dev/null 2>&1
if cmp -s -n "$(stat -c%s "$work/after-one.md")" "$work/after-one.md" "$s2/traj.md"; then
  printf 'ok   resume appends to the trajectory and never rewrites it\n'
else
  printf 'FAIL resume changed bytes the killed run had already written\n'; fail=1
fi
hasin "$s2/traj.md" 'turn=2 prompt=2400 hit=1024' 'the resumed turn is turn two, and the cache shows'

# the request itself: turn two extends turn one's messages instead of changing them
k=$(jq '.messages | length' "$s2/req.1.json")
if jq -c --argjson k "$k" '.messages[0:$k]' "$s2/req.2.json" >"$work/m2" &&
   jq -c '.messages' "$s2/req.1.json" >"$work/m1" && cmp -s "$work/m1" "$work/m2"; then
  printf 'ok   the second request repeats the first one byte for byte as its prefix\n'
else
  printf 'FAIL the second request does not start with the first\n'; fail=1
fi
hasin "$s2/req.1.json" 'You are an agent with no tools' 'the system prompt is what the request carries first'

((fail == 0)) && printf '\nall invariants hold\n' || printf '\nsomething above failed\n'
exit "$fail"
