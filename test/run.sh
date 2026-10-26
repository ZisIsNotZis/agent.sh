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

# the reporter uses builtin/command, so a block that shadows printf or wc changes nothing
cat >"$work/lie.sh" <<'BLOCKS'
printf() { local n=${1#SENT }; n=${n%% *}; builtin printf 'SENT %s 42 3\002' "$n"; }
wc() { echo 5; }
echo ABCDE
BLOCKS
AGENT_SH_SESSION_ROOT=$work/lie bash agent.sh --blocks "$work/lie.sh" --lines 1000 \
  >"$work/lie.out" 2>&1
hasin "$work/lie.out" 'Bash: ABCDE' 'shadowing printf does not let a block speak for the harness'
hasin "$work/lie.out" '[status 0]' 'the real status arrives despite a shadowed printf'
hasntin "$work/lie.out" '[status 42]' 'a shadowed printf cannot set the reported status'
hasntin "$work/lie.out" 'the boundary did not hold' 'and nothing about the boundary is disturbed'

# the residual, stated and checked: shadow `builtin` itself and the slip is forged — but the
# file is still the authority on size, so the lie is reported rather than believed
cat >"$work/residual.sh" <<'BLOCKS'
builtin() { local n=${2#SENT }; n=${n%% *}; command printf 'SENT %s 42 3\002' "$n"; }
echo ABCDE
BLOCKS
AGENT_SH_SESSION_ROOT=$work/residual bash agent.sh --blocks "$work/residual.sh" --lines 1000 \
  >"$work/residual.out" 2>&1
hasin "$work/residual.out" 'the boundary did not hold: the slip said 3 bytes and the file holds 6' \
  'a forged size is caught against the file, and said out loud'
hasin "$work/residual.out" 'ABCDE' 'the forged slip does not hide what the block really printed'
hasin "$work/residual.out" 'the status is the one the slip claimed, unproven' \
  'the forged status is shown as unproven rather than passed off as the block status'

# a stray byte on the control channel must not read as the hands dying
cat >"$work/stray.sh" <<'BLOCKS'
{ printf '\002' >&10; } 2>/dev/null; echo payload-ran
%%
echo still-here
BLOCKS
AGENT_SH_SESSION_ROOT=$work/stray bash agent.sh --blocks "$work/stray.sh" >"$work/stray.out" 2>&1
hasin "$work/stray.out" 'Bash: payload-ran' 'a stray boundary byte is skipped, not read as a death'
hasntin "$work/stray.out" 'the hands exited during this block' 'no false death is reported for a stray byte'

# a job that outlives its wait does not hang the run
cat >"$work/slow.sh" <<'BLOCKS'
bgrun -n slow-job sleep 5
BLOCKS
AGENT_SH_SESSION_ROOT=$work/slow AGENT_SH_JOB_WAIT=1 timeout 20 bash agent.sh --blocks "$work/slow.sh" \
  >"$work/slow.out" 2>&1
hasin "$work/slow.out" 'no job finished within 1s; 1 still running' \
  'a job that outlives the wait is reported, not waited on forever'

# a block that never ends must not eat the run: it is bounded, and the harness survives it
cat >"$work/stuck.sh" <<'BLOCKS'
echo before-the-hang
%%
sleep 30; echo never
%%
echo after-the-hang
BLOCKS
AGENT_SH_BLOCK_TIMEOUT=1 AGENT_SH_SESSION_ROOT=$work/stuck bash agent.sh --blocks "$work/stuck.sh" \
  >"$work/stuck.out" 2>&1
hasin "$work/stuck.out" '[this block ran longer than 1s and was killed' \
  'a block that never finishes is cut at the wall clock, with a status'
hasin "$work/stuck.out" '[status 124]' 'the timeout reports itself as a status, not a silence'
hasin "$work/stuck.out" 'after-the-hang' 'the harness is alive and serving after a timeout'
hasntin "$work/stuck.out" 'never' 'the killed block produced nothing after the cut'

# a fenced block would run twice, because backticks are a command substitution: it is unfenced
cat >"$work/fence.sh" <<'BLOCKS'
```
echo fenced
```
%%
echo after
BLOCKS
AGENT_SH_SESSION_ROOT=$work/fence bash agent.sh --blocks "$work/fence.sh" >"$work/fence.out" 2>&1
hasin "$work/fence.out" 'Bash: fenced' 'a fence around the whole block is stripped before it runs'
hasntin "$work/fence.out" 'command not found' 'the fence did not become a command substitution'

# the turn: a model in a file, so the loop, the meter and resume are all free to check
wake_stub=test/stub-model.sh
s1=$work/turn
bash agent.sh --task 'say hello and start a job' --session "$s1" --stub "$wake_stub" --max-turns 2 \
  >"$work/turn.out" 2>"$work/turn.err"
hasin "$work/turn.out" 'Bash: hello from turn one' 'a turn runs its reply as the block'
hasin "$work/turn.out" 'Job: job 1 exited 0' 'a job finishing between turns arrives as Job:'
hasin "$s1/traj.md" '<|meter|> turn=1 prompt=2000' 'the trajectory carries a meter line per turn'
hasin "$s1/traj.md" '<|meter|> turn=2' 'one meter line for each turn, in order'
hasin "$work/turn.err" 'cumulative prompt 7000' 'the meter totals across the session'

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
hasin "$s2/traj.md" 'turn=2 prompt=5000 hit=4800' 'the resumed turn is turn two, and the cache shows'

# the stop: a block with nothing to run ends the run instead of burning the turn budget
s4=$work/stop
bash agent.sh --task go --session "$s4" --stub "$wake_stub" --max-turns 10 >"$work/stop.out" 2>"$work/stop.err"
hasin "$work/stop.err" 'the block held nothing to run, so the run ends here (turn 6)' \
  'a comment-only block ends the run, at the turn it was written'
hasin "$s4/traj.md" '# done, and nothing left to run' 'the ending comment is recorded like any block'

# an empty reply is not a stop: it is a model saying nothing, and it is told so
s5=$work/empty
bash agent.sh --task go --session "$s5" --stub test/stub-empty.sh --max-turns 4 >"$work/empty.out" 2>&1
hasin "$s5/traj.md" 'that reply was empty, so nothing ran' 'an empty reply is answered, not obeyed'
hasin "$work/empty.out" 'the run ends here (turn 2)' 'the run goes on past an empty reply and stops at the comment'

# the request itself: turn two extends turn one's messages instead of changing them
k=$(jq '.messages | length' "$s2/req.1.json")
if jq -c --argjson k "$k" '.messages[0:$k]' "$s2/req.2.json" >"$work/m2" &&
   jq -c '.messages' "$s2/req.1.json" >"$work/m1" && cmp -s "$work/m1" "$work/m2"; then
  printf 'ok   the second request repeats the first one byte for byte as its prefix\n'
else
  printf 'FAIL the second request does not start with the first\n'; fail=1
fi
hasin "$s2/req.1.json" 'You are an agent with no tools' 'the system prompt is what the request carries first'

# compaction: an appended command, a summary, and one prefix rebuilt from it
s3=$work/compact
bash agent.sh --task 'go' --session "$s3" --stub "$wake_stub" --max-turns 6 --compact-at 4000 \
  >"$work/compact.out" 2>"$work/compact.err"
hasin "$s3/traj.md" '<|compact|> kept=' 'compaction appends a record with its boundary'
hasin "$s3/traj.md" '<|summary|>' 'compaction writes the summary it got back'
hasin "$s3/traj.md" '<|meter|> compact=1' 'the compaction call is metered too'
after=$(grep -n '^<|compact|>' "$s3/traj.md" | head -1 | cut -d: -f1)
if [[ -n $after ]] && sed -n "$((after + 1)),\$p" "$s3/traj.md" | grep -q '<|meter|> turn=3'; then
  printf 'ok   the turn after a boundary starts from the summary, not the old history\n'
else
  printf 'FAIL no turn follows the compaction boundary\n'; fail=1
fi
first_turn_after=$(ls "$s3"/req.*.json | while read -r f; do n=${f##*.}; done; echo)
if jq -e '.messages[1].content | startswith("User: [everything before this point, summarised]")' \
     "$s3"/req.3.json >/dev/null 2>&1; then
  printf 'ok   the rebuilt prefix is the summary, and it is at the front\n'
else
  printf 'FAIL the request after the boundary does not start with the summary\n'; fail=1
fi

# and the proof itself: the cache arithmetic, which must also be able to fail
if AGENT_SH=$PWD/agent.sh bash test/check-prefix.sh "$s3" >"$work/prefix.out" 2>&1; then
  printf 'ok   check-prefix passes a run whose prefixes held (%s)\n' \
    "$(grep -o '[0-9]* boundaries, [0-9]* checked, 0 failed' "$work/prefix.out" | head -1)"
else
  printf 'FAIL check-prefix rejected a healthy run\n'; cat "$work/prefix.out"; fail=1
fi
mkdir -p "$work/broken"
printf '<|meter|> turn=1 prompt=3000 hit=0 miss=3000 out=1 cum_prompt=3000\n<|meter|> turn=2 prompt=4000 hit=0 miss=4000 out=1 cum_prompt=7000\n' \
  >"$work/broken/traj.md"
if AGENT_SH=$PWD/agent.sh bash test/check-prefix.sh "$work/broken" >/dev/null 2>&1; then
  printf 'FAIL check-prefix passed a trajectory whose prefix was rewritten\n'; fail=1
else
  printf 'ok   check-prefix fails a trajectory whose prefix was rewritten\n'
fi

# an edited trajectory must fail too: the record has to rebuild what was actually sent
s6=$work/edited
bash agent.sh --task go --session "$s6" --stub "$wake_stub" --max-turns 2 >/dev/null 2>&1
sed -i 's/^User: go$/User: something else entirely/' "$s6/traj.md"
if AGENT_SH=$PWD/agent.sh bash test/check-prefix.sh "$s6" >/dev/null 2>&1; then
  printf 'FAIL check-prefix passed a trajectory that no longer rebuilds its requests\n'; fail=1
else
  printf 'ok   check-prefix fails a trajectory edited away from its requests\n'
fi
hasin "$s3/req.2.json" 'Job: job 1 exited 0' 'a Job: message is in the request, not invented in the record alone'

((fail == 0)) && printf '\nall invariants hold\n' || printf '\nsomething above failed\n'
exit "$fail"
