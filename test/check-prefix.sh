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

# the requests live beside the trajectory when the session root is the run directory, and in
# `session/` when the harness was pointed at a session inside it
reqdir=$dir
compgen -G "$dir/session/req.*.json" >/dev/null && reqdir=$dir/session

failed=0
boundaries=$(grep -c '^<|compact|>' "$traj" 2>/dev/null || true)
[ -n "${boundaries:-}" ] || boundaries=0

# --- 1. the trajectory is the request that was sent -----------------------------------------
requests=0
rebuilt=0
exempt_file=$(mktemp) || exit 73
prev_json=$(mktemp) || exit 73
trap 'rm -f "$exempt_file" "$prev_json"' EXIT

# the delivered trajectory must be the session's own copy: the milestone points at runs/<demo>/traj.md,
# so a check that replays session/traj.md while a reader reads another file proves nothing
if [[ -f $dir/session/traj.md ]] && ! cmp -s "$dir/session/traj.md" "$traj"; then
  printf 'the delivered trajectory is not the session one\n'
  printf 'FAIL %s and %s differ\n' "$traj" "$dir/session/traj.md"
  failed=1
fi

# A turn is exempt only when its request is *not* an extension of the one before it — the prefix
# really was rebuilt — and it carries the summary. Both facts are read off the requests that were
# actually sent, so a record edited on its own cannot create an exemption.
if compgen -G "$reqdir/req.*.json" >/dev/null; then
  printf 'the record rebuilds every request\n'
  for f in $(ls "$reqdir"/req.*.json | sed -n 's/.*\/req\.\([0-9][0-9]*\)\.json$/\1/p' | sort -n); do
    requests=$((requests + 1))
    sent_file=$(mktemp); rebuilt_file=$(mktemp)
    if ! jq -S . "$reqdir/req.$f.json" >"$sent_file" 2>/dev/null; then
      printf 'turn %-4s UNREADABLE request file\n' "$f"; failed=1; continue
    fi
    if bash "$agent" --replay "$reqdir" "$f" >"$rebuilt_file" 2>/dev/null &&
       cmp -s "$sent_file" "$rebuilt_file"; then
      rebuilt=$((rebuilt + 1))
      printf 'turn %-4s rebuilt from the trajectory, identical to what was sent\n' "$f"
    else
      printf 'turn %-4s THE RECORD DOES NOT REBUILD THIS REQUEST\n' "$f"; failed=1
    fi
    rm -f "$rebuilt_file"

    if [[ -s $prev_json ]]; then
      k=$(jq '.messages | length' "$prev_json")
      cur=$(jq -r '.messages[1].content // ""' "$sent_file")
      is_summary=0
      [[ $cur == 'User: [everything before this point, summarised]'* ]] && is_summary=1
      # a normal turn appends, so it must be strictly longer *and* contain the previous request;
      # an equal-length request means the prefix was rebuilt, even when the two look alike
      if (( $(jq '.messages | length' "$sent_file") > k )) &&
         jq -c --argjson k "$k" '.messages[0:$k]' "$sent_file" >"$sent_file.cut" 2>/dev/null &&
         cmp -s "$sent_file.cut" <(jq -c '.messages' "$prev_json"); then
        :   # an extension: the prefix held
      elif (( is_summary )); then
        printf 'turn %-4s rebuilt prefix: not an extension, and it carries a summary\n' "$f"
        printf '%s\n' "$f" >>"$exempt_file"
      else
        printf 'turn %-4s NOT AN EXTENSION, and no summary: the prefix was rebuilt without one\n' "$f"
        failed=1
      fi
      rm -f "$sent_file.cut"
    fi
    cp "$sent_file" "$prev_json"
    rm -f "$sent_file"
  done
else
  printf 'the record rebuilds every request: no req.*.json here, so this check cannot run\n'
  failed=1
fi

# --- 2. the cache found the previous prompt --------------------------------------------------
printf '\nthe cache arithmetic\n'
awk -v chunk=1024 -v exempt_list="$(tr '\n' ' ' <"$exempt_file")" '
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
    postboundary = (index(" " exempt_list " ", " " field($0, "turn") " ") > 0)
    if (exempt) { verdict = (postboundary ? "first request after a boundary, exempt" \
                                           : "INEXCUSABLE after a boundary: the request does not carry the summary"); if (!postboundary) failed++ ; exempt = 0 }
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
