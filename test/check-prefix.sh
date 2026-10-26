#!/usr/bin/env bash
# check-prefix.sh — the cache is the proof that the prefix never changed, so check it twice.
#
#   bash check-prefix.sh [trajectory.md | session directory]
#
# 1. The record rebuilds the request. For every turn this session sent, the harness rebuilds
#    the request from the trajectory alone (`agent.sh --replay`) and it must equal the request
#    that was actually sent, byte for byte after normalising key order. This is what makes the
#    meter numbers mean anything: without it a meter can be honest about a history that the
#    file no longer contains.
# 2. The provider found the previous prompt inside this one. For every request after the first,
#    `prompt_cache_hit_tokens >= previous prompt_tokens - 1024`, the 1024 being the smallest
#    cache chunk there is. A compaction boundary is the one exception by design — the request
#    after it is a freshly built prefix — so exactly the first request after a boundary is
#    exempt, and it must be a request that actually carries the summary.
#
# Exit 0 when both hold, 1 when either does not.
set -u
here=$(dirname "$0")
target=${1:-$here}
[[ -d $target ]] && target=$target/traj.md
[[ -r $target ]] || { printf 'check-prefix: no trajectory at %s\n' "$target" >&2; exit 66; }
dir=$(cd "$(dirname "$target")" && pwd)
traj=$dir/$(basename "$target")
traj_file=$(basename "$target")

find_agent() {
  local d; d=$dir
  while [[ $d != / ]]; do
    [[ -r $d/agent.sh ]] && { printf '%s' "$d/agent.sh"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}
agent=${AGENT_SH:-}
[[ -n $agent ]] || agent=$(find_agent) ||
  { printf 'check-prefix: no agent.sh above %s; set AGENT_SH\n' "$dir" >&2; exit 66; }

failed=0
boundaries=$(grep -c '^<|compact|>' "$traj" 2>/dev/null || true)
[ -n "${boundaries:-}" ] || boundaries=0

# --- 1. the trajectory is the request that was sent -----------------------------------------
requests=0
rebuilt=0
if compgen -G "$dir/req.*.json" >/dev/null; then
  printf 'the record rebuilds every request\n'
  for f in $(ls "$dir"/req.*.json | sed -n 's/.*\/req\.\([0-9][0-9]*\)\.json$/\1/p' | sort -n); do
    requests=$((requests + 1))
    if ! jq -S . "$dir/req.$f.json" >"$dir/.sent.$f" 2>/dev/null; then
      printf 'turn %-4s UNREADABLE request file\n' "$f"; failed=1; continue
    fi
    if bash "$agent" --replay "$dir" "$f" >"$dir/.rebuilt.$f" 2>/dev/null &&
       cmp -s "$dir/.sent.$f" "$dir/.rebuilt.$f"; then
      rebuilt=$((rebuilt + 1))
      printf 'turn %-4s rebuilt from the trajectory, identical to what was sent\n' "$f"
    else
      printf 'turn %-4s THE RECORD DOES NOT REBUILD THIS REQUEST\n' "$f"; failed=1
    fi
    rm -f "$dir/.sent.$f" "$dir/.rebuilt.$f"
  done
else
  printf 'the record rebuilds every request: no req.*.json here, so this check cannot run\n'
  failed=1
fi

# --- 2. the cache found the previous prompt --------------------------------------------------
printf '\nthe cache arithmetic\n'
awk -v chunk=1024 '
  function field(line, name,   i, a) {
    split(line, a, " ")
    for (i in a) if (index(a[i], name "=") == 1) return substr(a[i], length(name) + 2)
    return ""
  }
  /^<\|compact\|>/ { boundary++; next }
  /^<\|meter\|>/ {
    prompt = field($0, "prompt"); hit = field($0, "hit"); compact = field($0, "compact")
    n++
    label = (compact == "1") ? "compact" : "turn " field($0, "turn")
    if (exempt) { verdict = "first request after a boundary, exempt"; exempt = 0 }
    else if (n == 1) verdict = "first request, nothing to hit"
    else if (prev + 0 <= chunk) verdict = "previous prompt too small to verify against"
    else if (hit + 0 >= prev - chunk) { verdict = "prefix held (previous prompt " prev ")"; checked++ }
    else { verdict = "PREFIX LOST: previous prompt " prev " was not found"; checked++; failed++ }
    printf "%-9s prompt=%-7s hit=%-7s %s\n", label, prompt, hit, verdict
    prev = prompt
    if (compact == "1") exempt = 1
  }
  END {
    printf "%s requests, %s boundaries, %s checked, %s failed\n", n, boundary + 0, checked + 0, failed + 0
    exit (failed + 0 > 0)
  }
' "$traj" || failed=1

printf '\n'
if ((failed == 0)); then
  printf 'holds: %s requests rebuilt from the record, %s boundaries, no prefix lost\n' \
    "$rebuilt" "$boundaries"
else
  printf 'does not hold: see the lines above\n'
fi
exit "$failed"
