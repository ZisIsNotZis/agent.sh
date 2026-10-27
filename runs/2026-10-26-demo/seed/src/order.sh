#!/usr/bin/env bash
# order.sh — print one valid build order for the dependency pairs in $1 ("a b" means a needs b).
# Exit 0 with the order, or exit 1 printing `cycle: <packages>` when the input has a cycle.
set -u
file=${1:?usage: order.sh FILE}

# TODO: the cycle branch is missing. A cyclic input gets a partial order and a zero status,
# which is why report.txt has failures in it.
awk '
  { if (!($1 in need)) { need[$1] = 0 }; if (!($2 in need)) { need[$2] = 0 }
    if (($1 SUBSEP $2) in edge) next
    edge[$1 SUBSEP $2] = 1; need[$1]++ }
  END {
    n = 0
    for (p in need) if (need[p] == 0) queue[++n] = p
    head = 1
    while (head <= n) {
      p = queue[head++]; print p; done[p] = 1
      for (k in edge) { split(k, a, SUBSEP); if (a[2] == p) { if (--need[a[1]] == 0) queue[++n] = a[1] } }
    }
  }' "$file"
