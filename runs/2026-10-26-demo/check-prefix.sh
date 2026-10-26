#!/usr/bin/env bash
# check-prefix.sh — the cache is the proof that the prefix never changed, so check the arithmetic.
#
# For every request after the first, the provider should find the previous prompt inside this
# one: `prompt_cache_hit_tokens >= prompt_tokens_prev - 1024`, the 1024 being the smallest
# cache chunk there is. A compaction boundary is the one exception by design — the request
# after it is a freshly built prefix — so the first turn after a boundary is exempt, and every
# turn after that must be back in shape.
#
#   bash check-prefix.sh [trajectory.md or the session directory holding one]
#
# Exit 0 when every request outside a boundary holds, 1 when one does not.
set -u
here=$(dirname "$0")
target=${1:-$here}
[[ -d $target ]] && target=$target/traj.md
[[ -r $target ]] || { printf 'check-prefix: no trajectory at %s\n' "$target" >&2; exit 66; }

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
    printf "\n%s requests, %s boundaries, %s checked, %s failed\n", n, boundary + 0, checked + 0, failed + 0
    exit (failed + 0 > 0)
  }
' "$target"
