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
