#!/usr/bin/env bash
# order.sh — print one valid build order for the dependency pairs in $1 ("a b" means a needs b).
# Exit 0 with the order, or exit 1 printing `cycle: <packages>` when the input has a cycle.
set -u
file=${1:?usage: order.sh FILE}

awk '
  { nodes[$1] = 1; nodes[$2] = 1
    if (($1 SUBSEP $2) in edge) next
    edge[$1 SUBSEP $2] = 1; need[$1]++ }
  END {
    n = 0
    for (p in nodes) if (need[p] == 0) queue[++n] = p
    head = 1; order_n = 0
    while (head <= n) {
      p = queue[head++]
      if (p in printed) continue
      printed[p] = 1; order[++order_n] = p
      for (k in edge) {
        split(k, a, SUBSEP)
        if (a[2] != p || (a[1] in printed)) continue
        if (--need[a[1]] == 0) queue[++n] = a[1]
      }
    }
    if (order_n == length(nodes)) {
      for (i = 1; i <= order_n; i++) print order[i]
      exit 0
    }
    start = ""
    for (p in nodes) if (!(p in printed)) { start = p; break }
    u = start; len = 0
    while (!(u in idx)) {
      idx[u] = len; path[len] = u; len++
      nxt = ""
      for (k in edge) {
        split(k, a, SUBSEP)
        if (a[1] == u && !(a[2] in printed)) { nxt = a[2]; break }
      }
      if (nxt == "") break
      u = nxt
    }
    if (u in idx) {
      s = "cycle:"
      for (i = idx[u]; i < len; i++) s = s " " path[i]
      print s
    } else {
      print "cycle: " start
    }
    exit 1
  }' "$file"
