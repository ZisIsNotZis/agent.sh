#!/usr/bin/env bash
# agent.sh — an agent with no tools: what the model writes is executed by one long-lived bash.
#
# v0 driver, which makes no API call: `bash agent.sh --blocks <file> [--lines N]`.
# Blocks in <file> are separated by a line containing exactly `%%`, and each block's text
# stands in for what the model would have written. What comes back is the message a model
# would read: `Bash: ` at the front and `[status N]` at the end.
#
# The boundary is arithmetic, not a search: the block's output goes to a file, and the control
# pipe carries one slip `SENT <nonce> <exit> <bytes>` followed by \x02. Nothing in the payload
# can impersonate a slip, and the byte count is a free integrity check.
# SPDX-License-Identifier: AGPL-3.0-only — see LICENSE.

set -u

lines_max=100
blocks_file=''

while (($#)); do
  case $1 in
    --blocks) blocks_file=${2-}; shift 2 ;;
    --lines)  lines_max=${2-};   shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) printf 'agent.sh: unknown argument %s\n' "$1" >&2; exit 64 ;;
  esac
done
[[ -n $blocks_file ]] || { printf 'agent.sh: --blocks <file> is required in v0\n' >&2; exit 64; }
[[ -r $blocks_file ]] || { printf 'agent.sh: cannot read %s\n' "$blocks_file" >&2; exit 66; }
[[ $lines_max =~ ^[0-9]+$ ]] || { printf 'agent.sh: --lines takes a number\n' >&2; exit 64; }

sess=${AGENT_SH_SESSION_ROOT:-$PWD/.session}/$(date -u +%Y%m%dT%H%M%SZ)-$$
mkdir -p "$sess/raw" "$sess/out" "$sess/jobs" || exit 73
traj=$sess/traj.md
export AGENT_SH_SESSION=$sess AGENT_SH_JOBS=$sess/jobs

# --- the hands' env: the only two functions the model is given, and nothing else ------------
cat >"$sess/env.sh" <<'ENV'
# Sourced by the hands through BASH_ENV. Stateless and idempotent: subagent hands source it too.
bgrun() {
  local note='' seq d pid
  if [[ ${1-} == -n ]]; then note=${2-}; shift 2; fi
  (($#)) || { printf 'bgrun: nothing to run\n' >&2; return 2; }
  seq=$(( $(cat "$AGENT_SH_JOBS/seq" 2>/dev/null || printf 0) + 1 ))
  printf '%s\n' "$seq" >"$AGENT_SH_JOBS/seq"
  d=$AGENT_SH_JOBS/$seq
  mkdir -p "$d" || return 1
  printf '%s\n' "$note" >"$d/note"
  printf '%s\n' "$*"   >"$d/cmd"
  { "$@" ; } >"$d/log" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" >"$d/pid"
  printf 'job %s started, pid %s, log %s\n' "$seq" "$pid" "$d/log"
}

bgwait() {
  local pid='' st=0 c d=''
  wait -n -p pid; st=$?
  if ((st == 127)) || [[ -z $pid ]]; then printf 'no jobs pending\n'; return 127; fi
  for c in "$AGENT_SH_JOBS"/*/; do
    [[ $(cat "$c/pid" 2>/dev/null) == "$pid" ]] && { d=$c; break; }
  done
  if [[ -n $d ]]; then
    printf '%s\n' "$st" >"$d/status"
    note=$(cat "$d/note" 2>/dev/null)
    if [[ -n $note ]]; then
      printf 'job %s exited %s — note: %s\n' "$(basename "$d")" "$st" "$note"
    else
      printf 'job %s exited %s\n' "$(basename "$d")" "$st"
    fi
  else
    printf 'pid %s exited %s\n' "$pid" "$st"
  fi
  ((st == 0)) && return 0
  return "$st"
}
ENV
export BASH_ENV=$sess/env.sh

# --- the hands: a bash with no tty, in its own session, reachable only over the coproc ------
start_hands() {
  coproc HANDS { exec setsid bash --norc --noprofile 2>&1; }
}

# --- one block: transport the text as data, then take the output by byte count --------------
n=0      # blocks the model wrote
execs=0  # every call into the hands, wake calls included
polls=0
exec_block() {         # $1 body; sets raw chunk st bytes; 0 ok, 70 the write failed, 71 no slip, 72 desync
  local body=$1 nonce d t sz
  execs=$((execs + 1))
  raw=$sess/raw/$execs.raw
  chunk=$sess/out/$execs.txt
  nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
  d="__AGENT_${nonce}__"

  printf "read -r -d '' __b <<'%s'\n%s\n%s\n" "$d" "$body" "$d" >&"${HANDS[1]}" 2>/dev/null || return 70
  printf '%s' "eval -- \"\$__b\" >\"$raw\" 2>&1; __s=\$?; __n=\$(wc -c <\"$raw\"); printf 'SENT $nonce %d %d\x02' \"\$__s\" \"\$__n\"
" >&"${HANDS[1]}" 2>/dev/null || return 70
  IFS= read -r -d $'\x02' t <&"${HANDS[0]}" || return 71
  [[ $t == "SENT $nonce "* ]] || return 72
  read -r st sz <<<"${t#SENT $nonce }"

  head -c "$sz" "$raw" >"$chunk"
  bytes=$(wc -c <"$chunk")
  return 0
}

# what the hands printed, in the form the model reads: the window, and the refusal of bytes
show() {               # sets body
  local nul total
  nul=$(( bytes - $(tr -d '\0' <"$chunk" | wc -c) ))
  if ((nul > 0)) || ! iconv -f UTF-8 -t UTF-8 "$chunk" >/dev/null 2>&1; then
    body=$(printf '[binary output, %s bytes, not shown]' "$bytes")
  else
    total=$(wc -l <"$chunk")
    if ((total > lines_max)); then
      body=$(printf '[truncated: total %s lines, showing last %s; full output at %s]\n%s' \
        "$total" "$lines_max" "$raw" "$(tail -n "$lines_max" "$chunk")")
    elif ((bytes == 0)); then
      body=''
    else
      body=$(cat "$chunk")
    fi
  fi
}

run_block() {          # $1 body; prints the message and appends both sides to the trajectory
  local rc
  n=$((n + 1))
  exec_block "$1"; rc=$?
  case $rc in
    0) ;;
    70|71|72) return "$rc" ;;
    *) return 1 ;;
  esac
  show
  if [[ -n $body ]]; then msg=$(printf 'Bash: %s' "$body"); else msg='Bash:'; fi
  msg+=$(printf '\n[status %s]' "$st")
  printf '%s\n' "$msg"
  printf '<|assistant|>\n%s<|user|>\n%s\n' "$1" "$msg" >>"$traj"
  return 0
}

# a block that dies with its hands: say so once, and put fresh hands behind it
lost() {
  printf 'Bash: [the hands exited during this block, its output is lost, and a fresh bash is running]\n'
  [[ -n ${HANDS_PID-} ]] && kill "$HANDS_PID" 2>/dev/null
  wait "${HANDS_PID-}" 2>/dev/null
  start_hands
}

start_hands
block=''

deliver() {            # $1 body; 1 when the hands had to be replaced
  local rc
  run_block "$1"; rc=$?
  ((rc == 0)) && return 0
  lost
  return 1
}

# --- the wake: a finished job is a turn of its own, and no job pending means no poll -------
pending() {            # jobs with a pid and no status yet; counts them
  local c k=0
  for c in "$AGENT_SH_JOBS"/*/; do
    [[ -f $c/pid && ! -f $c/status ]] || continue
    k=$((k + 1))
  done
  printf '%s' "$k"
}

drain() {              # waits out the jobs, one Job: message per job, and counts the waits
  local c k
  while :; do
    (($(pending) > 0)) || return 0
    polls=$((polls + 1))
    if ! exec_block 'bgwait'; then
      # the hands are gone, so nothing can reap these jobs and their status is unknowable
      for c in "$AGENT_SH_JOBS"/*/; do
        [[ -f $c/pid && ! -f $c/status ]] || continue
        printf 'lost\n' >"$c/status"
      done
      lost
      printf 'Job: [the hands exited while jobs were pending; their status is unknown]\n'
      return 1
    fi
    show
    if [[ $body == 'no jobs pending' ]]; then
      # a job whose pid outlived its shell can never be reaped: record that, rather than poll on
      k=$(pending)
      for c in "$AGENT_SH_JOBS"/*/; do
        [[ -f $c/pid && ! -f $c/status ]] || continue
        printf 'lost\n' >"$c/status"
      done
      printf 'Job: [%s job(s) could not be reaped; their status is unknown]\n' "$k"
      return 0
    fi
    printf 'Job: %s\n' "$body"
    printf '<|assistant|>\nbgwait\n<|user|>\nJob: %s\n' "$body" >>"$traj"
  done
}

while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == '%%' ]]; then
    deliver "$block"; block=''
  else
    block+=$line$'\n'
  fi
done <"$blocks_file"
[[ -n $block ]] && deliver "$block"

# the file was the model, so the model has stopped writing: what is left is the jobs
(( $(pending) > 0 )) && drain

printf -- '--- %s blocks, %s polls, session %s\n' "$n" "$polls" "$sess" >&2
