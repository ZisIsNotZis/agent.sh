#!/usr/bin/env bash
# agent.sh — an agent with no tools: what the model writes is executed by one long-lived bash.
#
# Two drivers, and the same hands behind both.
#   bash agent.sh --task '<text>' [--session DIR] [--max-turns N] [--lines N] [--stub FILE]
#     the real one: one completions request per turn, the reply executed as the block, the
#     trajectory appended, a meter line per turn. `--resume` continues an existing session.
#   bash agent.sh --blocks <file> [--lines N]
#     the free one, which makes no API call: blocks separated by a line holding exactly `%%`
#     stand in for what the model would have written.
#
# The boundary is arithmetic, not a search: the block's output goes to a file, and the control
# pipe carries one slip `SENT <nonce> <exit> <bytes>` followed by \x02. Nothing in the payload
# can impersonate a slip, and the byte count is a free integrity check.
# SPDX-License-Identifier: AGPL-3.0-only — see LICENSE.

set -u

lines_max=100
blocks_file=''
task=''
sess=''
resume=''
stub=''
max_turns=8
usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0" | grep -v '^SPDX-'; }

while (($#)); do
  case $1 in
    --blocks) blocks_file=${2-}; shift 2 ;;
    --lines)  lines_max=${2-};   shift 2 ;;
    --task)   task=${2-};        shift 2 ;;
    --session) sess=${2-};       shift 2 ;;
    --resume) resume=1;          shift ;;
    --max-turns) max_turns=${2-}; shift 2 ;;
    --stub)   stub=${2-};        shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'agent.sh: unknown argument %s\n' "$1" >&2; exit 64 ;;
  esac
done
if [[ -n $blocks_file ]]; then task=''; fi
if [[ -z $blocks_file && -z ${task-} && -z ${resume-} ]]; then
  printf 'agent.sh: --blocks <file>, --task <text> or --resume is required\n' >&2; exit 64
fi
[[ -z $blocks_file || -r $blocks_file ]] || { printf 'agent.sh: cannot read %s\n' "$blocks_file" >&2; exit 66; }
[[ $lines_max =~ ^[0-9]+$ ]] || { printf 'agent.sh: --lines takes a number\n' >&2; exit 64; }
[[ $max_turns =~ ^[0-9]+$ ]] || { printf 'agent.sh: --max-turns takes a number\n' >&2; exit 64; }

sess=${sess:-${AGENT_SH_SESSION_ROOT:-$PWD/.session}/$(date -u +%Y%m%dT%H%M%SZ)-$$}
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
# a session that already ran resumes its numbering, so no raw file is overwritten
execs=$(find "$sess/raw" -name '*.raw' 2>/dev/null | wc -l)
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
  # the record keeps one newline between the block and the reply, whatever the block's tail
  local rec=${1%$'\n'}; rec=${rec%$'\n'}
  printf '<|assistant|>\n%s\n<|user|>\n%s\n' "$rec" "$msg" >>"$traj"
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

run_blocks() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == '%%' ]]; then
      deliver "$block"; block=''
    else
      block+=$line$'\n'
    fi
  done <"$blocks_file"
  [[ -n $block ]] && deliver "$block"
  # the file was the model, so the model has stopped writing: what is left is the jobs
  (($(pending) > 0)) && drain
  printf -- '--- %s blocks, %s polls, session %s\n' "$n" "$polls" "$sess" >&2
}

# --- the turn: one completions request, its reply executed as this turn's block ------------
api=${AGENT_SH_API:-https://api.deepseek.com/chat/completions}
model=${AGENT_SH_MODEL:-deepseek-flash}
effort=${AGENT_SH_EFFORT:-low}
max_tokens=${AGENT_SH_MAX_TOKENS:-4096}
prompt_file=${AGENT_SH_PROMPT:-$(dirname "$0")/prompt/system.md}
# a resumed session keeps its totals, taken from the meter lines it already carries
read -r cum_pt cum_hit cum_miss cum_out < <(awk '
  /^<\|meter\|> / { for (i = 1; i <= NF; i++) if ($i ~ /^(prompt|hit|miss|out)=/) {
    split($i, kv, "="); s[kv[1]] += kv[2] } }
  END { printf "%d %d %d %d\n", s["prompt"], s["hit"], s["miss"], s["out"] }' "$traj" 2>/dev/null)
cum_pt=${cum_pt:-0}; cum_hit=${cum_hit:-0}; cum_miss=${cum_miss:-0}; cum_out=${cum_out:-0}
turn_i=$(grep -c '^<|meter|>' "$traj" 2>/dev/null || true)

[[ -r $prompt_file ]] || { printf 'agent.sh: no system prompt at %s\n' "$prompt_file" >&2; exit 66; }

traj_msgs() {          # the trajectory as NUL-separated (role, content) pairs
  awk '
    function emit() { sub(/\n$/, "", buf); printf "%s%c%s%c", role, 0, buf, 0 }
    $0 == "<|assistant|>" || $0 == "<|user|>" {
      if (role != "") emit()
      role = ($0 == "<|user|>") ? "user" : "assistant"; buf = ""; next
    }
    { buf = buf $0 "\n" }
    END { if (role != "") emit() }
  ' "$traj"
}

build_request() {      # $1 out file: system prompt, then every message, verbatim
  local out=$1 role content
  : >"$sess/msgs.jsonl"
  jq -cn --rawfile c "$prompt_file" '{role:"system",content:$c}' >>"$sess/msgs.jsonl"
  while IFS= read -r -d '' role && IFS= read -r -d '' content; do
    jq -cn --arg r "$role" --arg c "$content" '{role:$r,content:$c}' >>"$sess/msgs.jsonl"
  done < <(traj_msgs)
  jq -s --arg model "$model" --arg effort "$effort" --argjson max "$max_tokens" \
    '{model:$model, reasoning_effort:$effort, max_tokens:$max, messages:.}' \
    "$sess/msgs.jsonl" >"$out"
}

complete() {           # $1 request, $2 response: the one place a network call can happen
  if [[ -n $stub ]]; then
    bash "$stub" "$1" "$2"
  else
    curl -sS --max-time 600 "$api" \
      -H "Authorization: Bearer ${DEEPSEEK_API_KEY-}" \
      -H 'Content-Type: application/json' \
      --data-binary @"$1" -o "$2"
  fi
}

turn() {               # request, block, trajectory, meter; 0 ok
  local req=$sess/req.json res=$sess/res.json reply rc pt hit miss out
  turn_i=$((turn_i + 1))
  build_request "$req"
  cp "$req" "$sess/req.$turn_i.json"
  if ! complete "$req" "$res"; then
    printf 'agent.sh: turn %s: the request did not complete\n' "$turn_i" >&2; return 1
  fi
  if [[ $(jq -r 'has("error")' "$res" 2>/dev/null) == true ]]; then
    printf 'agent.sh: turn %s: %s\n' "$turn_i" "$(jq -r '.error.message // (.error|tostring)' "$res")" >&2
    return 1
  fi
  reply=$(jq -r '.choices[0].message.content // ""' "$res") || { printf 'agent.sh: turn %s: unreadable reply\n' "$turn_i" >&2; return 1; }

  run_block "$reply"; rc=$?
  ((rc == 0)) || lost

  pt=$(jq -r '.usage.prompt_tokens // 0' "$res")
  hit=$(jq -r '.usage.prompt_cache_hit_tokens // 0' "$res")
  miss=$(jq -r '.usage.prompt_cache_miss_tokens // 0' "$res")
  out=$(jq -r '.usage.completion_tokens // 0' "$res")
  cum_pt=$((cum_pt + pt)); cum_hit=$((cum_hit + hit)); cum_miss=$((cum_miss + miss)); cum_out=$((cum_out + out))
  printf '<|meter|> turn=%s prompt=%s hit=%s miss=%s out=%s cum_prompt=%s\n' \
    "$turn_i" "$pt" "$hit" "$miss" "$out" "$cum_pt" >>"$traj"
  printf 'meter: turn %s prompt %s (hit %s, miss %s), out %s, cumulative prompt %s\n' \
    "$turn_i" "$pt" "$hit" "$miss" "$out" "$cum_pt" >&2
  return 0
}

run_task() {
  [[ -n ${task-} ]] && printf '<|user|>\nUser: %s\n' "$task" >>"$traj"
  while ((turn_i < max_turns)); do
    turn || return 1
    (($(pending) > 0)) && drain
  done
  printf -- '--- %s turns, %s polls, %s spent prompt tokens, session %s\n' \
    "$turn_i" "$polls" "$cum_pt" "$sess" >&2
}

if [[ -n $blocks_file ]]; then run_blocks; else run_task; fi
