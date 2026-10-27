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
# The boundary is a file, not a stream. The block is written to its own file with one line
# appended — `>"$slipdir/<nonce>.$?"` — which is a redirection with no command word, so the shell
# parser writes the block's status into a file name after the block has run. A redirection cannot
# be shadowed by a function the block defines, so the report is the one thing a block cannot fake
# with a builtin. The output itself is read from its own file by byte count.
# What remains is the no-sandbox line and is written down in docs/design.md, not claimed away: a
# block that reads its own file can find the nonce, and can write a slip file itself.
# SPDX-License-Identifier: AGPL-3.0-only — see LICENSE.

set -u

lines_max=100
blocks_file=''
task=''
sess=''
resume=''
stub=''
max_turns=8
compact_at=0
replay=0
replay_turn=0
cut_assistant=0   # when set, the parser stops before this assistant message (for --replay)
block_timeout=${AGENT_SH_BLOCK_TIMEOUT:-300}
job_wait=${AGENT_SH_JOB_WAIT:-600}
usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0" | grep -v '^SPDX-'; }

while (($#)); do
  case $1 in
    --blocks) blocks_file=${2-}; shift 2 ;;
    --lines)  lines_max=${2-};   shift 2 ;;
    --task)   task=${2-};        shift 2 ;;
    --session) sess=${2-};       shift 2 ;;
    --resume) resume=1;          shift ;;
    --max-turns) max_turns=${2-}; shift 2 ;;
    --compact-at) compact_at=${2-}; shift 2 ;;
    --stub)   stub=${2-};        shift 2 ;;
    --replay) replay=1; sess=${2-}; replay_turn=${3-}; shift 3 || shift $# ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'agent.sh: unknown argument %s\n' "$1" >&2; exit 64 ;;
  esac
done
if [[ -n $blocks_file ]]; then task=''; fi
if [[ -z $blocks_file && -z ${task-} && -z ${resume-} ]] && ((replay == 0)); then
  printf 'agent.sh: --blocks <file>, --task <text>, --resume or --replay is required\n' >&2; exit 64
fi
[[ -z $blocks_file || -r $blocks_file ]] || { printf 'agent.sh: cannot read %s\n' "$blocks_file" >&2; exit 66; }
[[ $lines_max =~ ^[0-9]+$ ]] || { printf 'agent.sh: --lines takes a number\n' >&2; exit 64; }
[[ $max_turns =~ ^[0-9]+$ ]] || { printf 'agent.sh: --max-turns takes a number\n' >&2; exit 64; }
[[ $compact_at =~ ^[0-9]+$ ]] || { printf 'agent.sh: --compact-at takes a number\n' >&2; exit 64; }
# a wait of zero would mean "forever", which is the failure this bound exists to prevent
[[ $block_timeout =~ ^[1-9][0-9]*$ ]] || { printf 'agent.sh: AGENT_SH_BLOCK_TIMEOUT must be a positive number\n' >&2; exit 64; }
[[ $job_wait =~ ^[1-9][0-9]*$ ]] || { printf 'agent.sh: AGENT_SH_JOB_WAIT must be a positive number\n' >&2; exit 64; }


sess=${sess:-${AGENT_SH_SESSION_ROOT:-$PWD/.session}/$(date -u +%Y%m%dT%H%M%SZ)-$$}
traj=$sess/traj.md
export AGENT_SH_SESSION=$sess AGENT_SH_JOBS=$sess/jobs
# `--replay` only reads: it writes its scratch files to a temporary directory of its own, so a
# check of a session cannot change the session it is checking
scratch=$sess
if ((replay)); then
  scratch=$(mktemp -d) || exit 73
  trap 'rm -rf "$scratch"' EXIT
fi
slipdir=$sess/slip
((replay)) || { mkdir -p "$sess/raw" "$sess/out" "$sess/jobs" "$sess/blk" "$slipdir" || exit 73; }

# --- the hands' env: the only two functions the model is given, and nothing else ------------
cat >"$scratch/env.sh" <<'ENV'
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
export BASH_ENV=$scratch/env.sh

# --- the hands: a bash with no tty, in its own session, reachable only over the coproc ------
start_hands() {
  rm -f "$sess/hands.pid"
  # the hands write nothing the harness reads over the pipe any more: its stdout goes to a log
  # so a chatty block cannot fill a pipe nobody drains
  coproc HANDS { exec setsid bash --norc --noprofile >>"$sess/hands.log" 2>&1; }
  # `setsid` may fork, so the coproc's own pid is not the hands': have the hands say who it is
  printf 'printf "%%s\n" "$$" >"%s"\n' "$sess/hands.pid" >&"${HANDS[1]}" 2>/dev/null
}

# --- one block: transport the text as data, then take the output by byte count --------------
n=0      # blocks the model wrote
execs=0  # every call into the hands, wake calls included
# a session that already ran resumes its numbering, so no raw file is overwritten
execs=$(find "$sess/raw" -name '*.raw' 2>/dev/null | wc -l)
polls=0
exec_block() {         # $1 body, $2 seconds to wait; sets raw chunk st bytes
  local body=$1 tmo=${2-$block_timeout} nonce blk found start left w   # st, bytes: global
  execs=$((execs + 1))
  raw=$sess/raw/$execs.raw
  chunk=$sess/out/$execs.txt
  blk=$sess/blk/$execs.sh
  nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')

  # The block travels as a file the harness writes, not as a heredoc the shell has to read:
  # nothing quotes it, nothing can corrupt it, and the slip line comes last inside the same
  # file, so it runs after the block, in the block's own shell, with the block's own status.
  # That line is a redirection with no command word — `>"$dir/$nonce.$?"` — and a redirection is
  # the shell's own parser, which no function a block defines can shadow or replace.
  { printf '%s\n' "$body"; printf '>"%s/%s.$?"\n' "$slipdir" "$nonce"; } >"$blk" || return 70

  # A block that does not parse never reaches the hands: its shell state is untouched and the
  # error is an ordinary result instead of a wait that ends in a timeout.
  if ! command bash -n "$blk" 2>/dev/null; then
    command bash -n "$blk" 2>"$raw"
    bytes=$(command wc -c <"$raw"); command head -c "$bytes" "$raw" >"$chunk"
    st=2
    return 0
  fi

  printf '. "%s" >"%s" 2>&1\n' "$blk" "$raw" >&"${HANDS[1]}" 2>/dev/null || return 70

  # the slip is a file, so the harness has to look for it; the nonce in its name is what makes
  # a stale or forged file useless, and the clock is what keeps a block from hanging the run
  start=$(date +%s)
  while :; do
    set -- "$slipdir/$nonce".*
    if [[ -e $1 ]]; then found=$1; break; fi
    # a block that ended its own shell (`exit 7`) leaves no slip: say that at once rather than
    # waiting out the clock for something that is never coming
    hp=$(command cat "$sess/hands.pid" 2>/dev/null)
    if [[ -n $hp ]] && ! kill -0 "$hp" 2>/dev/null; then return 71; fi
    left=$((start + tmo - $(date +%s)))
    ((left > 0)) || return 73
    command sleep 0.02
  done
  st=${found##*/}; st=${st#"$nonce".}
  [[ $st =~ ^[0-9]+$ ]] || st='?'
  bytes=$(command wc -c <"$raw")
  command head -c "$bytes" "$raw" >"$chunk"
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

# a markdown fence is a command substitution to bash: the block would run, and then run again
# with its own output as the command. Strip one when the whole block is wrapped in one.
unfence() {            # $1 body; prints the body to execute
  local b=$1 first last
  first=${b%%$'\n'*}
  last=$(printf '%s\n' "$b" | awk 'NF { l = $0 } END { print l }')
  if [[ $first =~ ^\`\`\`[A-Za-z0-9_+.-]*$ && $last == '```' ]]; then
    printf '%s\n' "$b" | awk '{ line[NR] = $0 }
      END { n = NR; while (n > 1 && line[n] ~ /^[[:space:]]*$/) n--
            for (i = 1; i <= NR; i++) if (i != 1 && i != n) print line[i] }'
  else
    printf '%s' "$b"
  fi
}

run_block() {          # $1 body, $2 a note to append after the status; prints, records
  local rc note=${2-}
  n=$((n + 1))
  exec_block "$(unfence "$1")" "${3-$block_timeout}"; rc=$?
  case $rc in
    0) ;;
    73)
      # the block is still running and the hands are the only thing holding it: kill them
      msg=$(printf '[this block ran longer than %ss and was killed, so the shell state it built is gone and a fresh bash is running]' "$block_timeout")
      msg=$(printf 'Bash: %s\n[status 124]' "$msg")
      printf '%s\n' "$msg"
      printf '<|assistant|>\n%s\n<|user|>\n%s\n' "$(unfence "$1")" "$msg" >>"$traj"
      restart_hands
      return 0 ;;
    70|71|72) return "$rc" ;;
    *) return 1 ;;
  esac
  show
  if [[ -n $body ]]; then msg=$(printf 'Bash: %s' "$body"); else msg='Bash:'; fi
  msg+=$(printf '\n[status %s]' "$st")
  [[ -n $note ]] && msg+=$(printf '\n[%s]' "$note")
  printf '%s\n' "$msg"
  # the record keeps one newline between the block and the reply, whatever the block's tail
  local rec; rec=$(unfence "$1"); rec=${rec%$'\n'}; rec=${rec%$'\n'}
  printf '<|assistant|>\n%s\n<|user|>\n%s\n' "$rec" "$msg" >>"$traj"
  return 0
}

# a block that dies with its hands: say so once, and put fresh hands behind it
restart_hands() {
  # the hands lead their own session, so killing its process group takes the whole tree with
  # it and nothing keeps a job's log open
  local hp pg
  hp=$(cat "$sess/hands.pid" 2>/dev/null)
  if [[ -n $hp ]]; then
    pg=$(ps -o pgid= -p "$hp" 2>/dev/null | tr -d ' ')
    [[ -n $pg ]] && kill -- "-$pg" 2>/dev/null
    kill "$hp" 2>/dev/null
  fi
  [[ -n ${HANDS_PID-} ]] && kill "$HANDS_PID" 2>/dev/null
  wait "${HANDS_PID-}" 2>/dev/null
  start_hands
}

lost() {
  printf 'Bash: [the hands exited during this block, its output is lost, and a fresh bash is running]\n'
  restart_hands
}

((replay)) || start_hands
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
  local c k rc k_prev
  while :; do
    k_prev=$(pending)
    ((k_prev > 0)) || return 0
    polls=$((polls + 1))
    exec_block 'bgwait' "$job_wait"; rc=$?
    if ((rc == 73)); then
      # a job that outlives the wait is not a reason to end an unattended run: say so, leave it
      # pending, and let a later drain collect it
      printf 'Job: [no job finished within %ss; %s still running]\n' "$job_wait" "$(pending)"
      printf '<|user|>\nJob: [no job finished within %ss; %s still running]\n' \
        "$job_wait" "$(pending)" >>"$traj"
      return 0
    fi
    if ((rc != 0)); then
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
    # the harness waited, not the model: the record carries the message and no invented block
    k=$((k_prev))
    printf 'Job: %s\n' "$body"
    printf '<|user|>\nJob: %s\n' "$body" >>"$traj"
    # a message is only a reap if the job table says so; a hands that answers without reaping
    # would otherwise spin here forever, printing a job that never finished
    if (($(pending) >= k_prev)); then
      for c in "$AGENT_SH_JOBS"/*/; do
        [[ -f $c/pid && ! -f $c/status ]] || continue
        printf 'lost\n' >"$c/status"
      done
      printf 'Job: [that message did not reap anything; the job table is unchanged]\n' >&2
      return 1
    fi
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
turn_i=$(grep '^<|meter|>' "$traj" 2>/dev/null | grep -vc 'compact=1' || true)
compacts=$(grep -c '^<|compact|>' "$traj" 2>/dev/null || true)
last_pt=$(grep '^<|meter|>' "$traj" 2>/dev/null | grep -v 'compact=1' | tail -1 | sed -n 's/.*prompt=\([0-9]*\).*/\1/p')
last_pt=${last_pt:-0}

[[ -r $prompt_file ]] || { printf 'agent.sh: no system prompt at %s\n' "$prompt_file" >&2; exit 66; }

# --- the trajectory is the only store: read it back as records, NUL-separated field by field
# msg\0role\0content\0 | meter\0line\0 | compact\0kept\0 | summary\0text\0
# NUL is safe as a separator because binary output is refused, so no body can contain one.
parse_traj() {         # fills mrole, mcontent, kept (messages to skip), sumtext
  local t a b
  mrole=(); mcontent=(); kept=0; sumtext=''
  while IFS= read -r -d '' t; do
    case $t in
      msg)     IFS= read -r -d '' a; IFS= read -r -d '' b; mrole+=("$a"); mcontent+=("$b") ;;
      summary) IFS= read -r -d '' a; sumtext=$a ;;
      compact) IFS= read -r -d '' a; kept=$a ;;
      meter)   IFS= read -r -d '' a ;;
    esac
  done < <(awk -v cut="$cut_assistant" '
    function flush() {
      if (role == "") return
      sub(/\n$/, "", buf)
      if (role == "summary") printf "summary%c%s%c", 0, buf, 0
      else printf "msg%c%s%c%s%c", 0, role, 0, buf, 0
      buf = ""; role = ""
    }
    $0 == "<|assistant|>" || $0 == "<|user|>" {
      flush()
      if ($0 == "<|assistant|>" && cut > 0 && ++seen >= cut) { exit }
      role = ($0 == "<|user|>") ? "user" : "assistant"; buf = ""; next
    }
    $0 == "<|summary|>" { flush(); role = "summary"; buf = ""; next }
    /^<\|meter\|>/   { flush(); printf "meter%c%s%c", 0, $0, 0; next }
    /^<\|compact\|>/ { flush(); printf "compact%c%s%c", 0, substr($0, index($0, "kept=") + 5), 0; next }
    { buf = buf $0 "\n" }
    END { flush() }
  ' "$traj")
}

build_request() {      # $1 out file, $2 an extra user message appended for this call
  local out=$1 extra=${2-} i
  parse_traj
  : >"$scratch/msgs.jsonl"
  jq -cn --rawfile c "$prompt_file" '{role:"system",content:$c}' >>"$scratch/msgs.jsonl"
  if [[ -n $sumtext ]]; then
    # the compacted history rides as one user message, so it is stable prefix and not system noise
    jq -cn --arg c "User: [everything before this point, summarised]
$sumtext" '{role:"user",content:$c}' >>"$scratch/msgs.jsonl"
  fi
  for ((i = kept; i < ${#mrole[@]}; i++)); do
    jq -cn --arg r "${mrole[i]}" --arg c "${mcontent[i]}" '{role:$r,content:$c}' >>"$scratch/msgs.jsonl"
  done
  if [[ -n $extra ]]; then
    jq -cn --arg c "$extra" '{role:"user",content:$c}' >>"$scratch/msgs.jsonl"
  fi
  jq -s --arg model "$model" --arg effort "$effort" --argjson max "$max_tokens" \
    '{model:$model, reasoning_effort:$effort, max_tokens:$max, messages:.}' \
    "$scratch/msgs.jsonl" >"$out"
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
  local req res reply rc pt hit miss out
  turn_i=$((turn_i + 1))
  req=$sess/req.$turn_i.json
  res=$sess/res.$turn_i.json
  build_request "$req"
  if ! complete "$req" "$res"; then
    printf 'agent.sh: turn %s: the request did not complete\n' "$turn_i" >&2; return 1
  fi
  if [[ $(jq -r 'has("error")' "$res" 2>/dev/null) == true ]]; then
    printf 'agent.sh: turn %s: %s\n' "$turn_i" "$(jq -r '.error.message // (.error|tostring)' "$res")" >&2
    return 1
  fi
  reply=$(jq -r '.choices[0].message.content // ""' "$res") || { printf 'agent.sh: turn %s: unreadable reply\n' "$turn_i" >&2; return 1; }

  # what the reply is, before it runs: markup and silence are answered, and a block with
  # nothing to run is how the agent says it is finished — there is no tool to call to stop,
  # so the empty command list is the stop and a `#` line is the report.
  reply_body=$(unfence "$reply")
  reply_note=''
  stop_now=0
  if [[ $reply == *DSML* || $reply == *'invoke name='* ]]; then
    reply_note='note: that is tool-call markup and there are no tools. Your whole reply is bash: write commands, and use # for what you want to say'
  elif ! grep -qvE '^[[:space:]]*$' <<<"$reply_body"; then
    reply_note='note: that reply was empty, so nothing ran. Write the bash block you mean to run'
  elif grep -qE '^[[:space:]]*#' <<<"$reply_body" && ! grep -qvE '^[[:space:]]*(#|$)' <<<"$reply_body"; then
    stop_now=1
  fi
  run_block "$reply" "$reply_note"; rc=$?
  ((rc == 0)) || lost

  pt=$(jq -r '.usage.prompt_tokens // 0' "$res")
  hit=$(jq -r '.usage.prompt_cache_hit_tokens // 0' "$res")
  miss=$(jq -r '.usage.prompt_cache_miss_tokens // 0' "$res")
  out=$(jq -r '.usage.completion_tokens // 0' "$res")
  cum_pt=$((cum_pt + pt)); cum_hit=$((cum_hit + hit)); cum_miss=$((cum_miss + miss)); cum_out=$((cum_out + out))
  last_pt=$pt
  printf '<|meter|> turn=%s prompt=%s hit=%s miss=%s out=%s cum_prompt=%s\n' \
    "$turn_i" "$pt" "$hit" "$miss" "$out" "$cum_pt" >>"$traj"
  printf 'meter: turn %s prompt %s (hit %s, miss %s), out %s, cumulative prompt %s\n' \
    "$turn_i" "$pt" "$hit" "$miss" "$out" "$cum_pt" >&2
  return 0
}

# --- /compact: an appended message, a summary, and a prefix that changes exactly once ------
compact_cmd='User: /compact — summarise this conversation for a fresh start: the task, what was tried
and what it showed, what is true now (paths, job state, decisions), and what is left. Write it
as plain text for another incarnation of yourself. Do not run anything: this reply is the
summary, not a block.'


compact() {            # appends the command, then a compact record carrying the summary
  local req=$sess/req.compact.$((compacts + 1)).json res=$sess/res.compact.$((compacts + 1)).json
  local summary pt hit miss out before
  parse_traj; before=${#mrole[@]}
  build_request "$req" "$compact_cmd"
  complete "$req" "$res" || { printf 'agent.sh: compaction: the request did not complete\n' >&2; return 1; }
  summary=$(jq -r '.choices[0].message.content // ""' "$res")
  [[ -n $summary ]] || { printf 'agent.sh: compaction: an empty summary, so nothing was compacted\n' >&2; return 1; }
  # the command is a real user message, and the record is what a resumed run rebuilds from
  printf '<|user|>\nUser: /compact\n' >>"$traj"
  printf '<|compact|> kept=%s\n<|summary|>\n%s\n' "$((before + 1))" "$summary" >>"$traj"
  compacts=$((compacts + 1))
  pt=$(jq -r '.usage.prompt_tokens // 0' "$res")
  hit=$(jq -r '.usage.prompt_cache_hit_tokens // 0' "$res")
  miss=$(jq -r '.usage.prompt_cache_miss_tokens // 0' "$res")
  out=$(jq -r '.usage.completion_tokens // 0' "$res")
  cum_pt=$((cum_pt + pt)); cum_hit=$((cum_hit + hit)); cum_miss=$((cum_miss + miss)); cum_out=$((cum_out + out))
  printf '<|meter|> compact=1 prompt=%s hit=%s miss=%s out=%s cum_prompt=%s\n' \
    "$pt" "$hit" "$miss" "$out" "$cum_pt" >>"$traj"
  printf 'compact: boundary %s after %s messages, prompt %s (hit %s), summary %s chars\n' \
    "$compacts" "$before" "$pt" "$hit" "${#summary}" >&2
  return 0
}

run_task() {
  [[ -n ${task-} ]] && printf '<|user|>\nUser: %s\n' "$task" >>"$traj"
  while ((turn_i < max_turns)); do
    turn || return 1
    if ((stop_now)); then
      printf 'agent.sh: the block held nothing to run, so the run ends here (turn %s)\n' "$turn_i" >&2
      break
    fi
    (($(pending) > 0)) && drain
    if ((compact_at > 0 && last_pt >= compact_at)); then compact; fi
  done
  printf -- '--- %s turns, %s polls, %s spent prompt tokens, session %s\n' \
    "$turn_i" "$polls" "$cum_pt" "$sess" >&2
}

# `--replay <session> <turn>`: rebuild what turn <turn> would have sent, from the trajectory
# alone. It is how check-prefix proves the record and the requests are the same thing.
if ((replay)); then
  [[ -r $traj && $replay_turn =~ ^[1-9][0-9]*$ ]] || {
    printf 'agent.sh: --replay needs a session with a trajectory and a turn number\n' >&2; exit 64; }
  cut_assistant=$replay_turn
  build_request "$scratch/replay.json"
  jq -S . "$scratch/replay.json"
  exit 0
fi

if [[ -n $blocks_file ]]; then run_blocks; else run_task; fi
