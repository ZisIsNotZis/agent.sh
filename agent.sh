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
    printf 'job %s exited %s\n' "$(basename "$d")" "$st"
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
n=0
run_block() {          # $1 body; sets msg; returns 0 ok, 70 the write failed, 71 no slip, 72 desync
  local body=$1 nonce d t st sz raw chunk bytes total nul
  n=$((n + 1))
  raw=$sess/raw/$n.raw
  chunk=$sess/out/$n.txt
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
  nul=$(( bytes - $(tr -d '\0' <"$chunk" | wc -c) ))
  if ((nul > 0)) || ! iconv -f UTF-8 -t UTF-8 "$chunk" >/dev/null 2>&1; then
    msg=$(printf 'Bash: [binary output, %s bytes, not shown]' "$bytes")
  else
    total=$(wc -l <"$chunk")
    if ((total > lines_max)); then
      msg=$(printf 'Bash: [truncated: total %s lines, showing last %s; full output at %s]\n%s' \
        "$total" "$lines_max" "$raw" "$(tail -n "$lines_max" "$chunk")")
    elif ((bytes == 0)); then
      msg='Bash:'
    else
      msg=$(printf 'Bash: %s' "$(cat "$chunk")")
    fi
  fi
  msg+=$(printf '\n[status %s]' "$st")

  printf '%s\n' "$msg"
  printf '<|assistant|>\n%s<|user|>\n%s\n' "$body" "$msg" >>"$traj"
  return 0
}

start_hands
block=''

deliver() {            # $1 body
  local rc
  run_block "$1"; rc=$?
  case $rc in
    0) return 0 ;;
    70|71|72)
      printf 'Bash: [the hands exited during this block, its output is lost, and a fresh bash is running]\n'
      [[ -n ${HANDS_PID-} ]] && kill "$HANDS_PID" 2>/dev/null
      wait "${HANDS_PID-}" 2>/dev/null
      start_hands
      return 1 ;;
    *) return 1 ;;
  esac
}

while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == '%%' ]]; then
    deliver "$block"; block=''
  else
    block+=$line$'\n'
  fi
done <"$blocks_file"
[[ -n $block ]] && deliver "$block"

printf -- '--- %s blocks, session %s\n' "$n" "$sess" >&2
