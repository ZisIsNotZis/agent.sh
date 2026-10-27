Bench report is in (120013 ms wall, 0.0 edges/ms). Now the bug is clear: `order.sh` has no cycle branch — cyclic inputs just emit a partial order with exit 0. I'll rewrite it with Kahn plus a real cycle extractor.

cat > src/order.sh <<'ORDER_EOF'
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
    # --- Kahn: start from packages that need nothing, peel them off ---
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

    # --- acyclic: print one valid order ---
    if (order_n == length(nodes)) {
      for (i = 1; i <= order_n; i++) print order[i]
      exit 0
    }

    # --- cyclic: every unprinted node still has an unprinted dependency, so
    #     following dependency edges must revisit a node; the first repeat
    #     closes a genuine cycle. ---
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
      if (nxt == "") break            # defensive: cannot happen for a real leftover
      u = nxt
    }

    if (u in idx) {
      s = "cycle:"
      for (i = idx[u]; i < len; i++) s = s " " path[i]
      print s
    } else {
      print "cycle: " start         # defensive fallback, still a cycle marker
    }
    exit 1
  }' "$file"
ORDER_EOF
chmod +x src/order.sh
echo "--- syntax check ---"
bash -n src/order.sh && echo OK
echo "--- smoke: acyclic ---"
printf 'a b\nb c\n' > /tmp/t1; ./src/order.sh /tmp/t1; echo "rc=$?"
echo "--- smoke: cycle ---"
printf 'a b\nb c\nc a\n' > /tmp/t2; ./src/order.sh /tmp/t2; echo "rc=$?"
echo "--- smoke: self loop ---"
printf 'a a\n' > /tmp/t3; ./src/order.sh /tmp/t3; echo "rc=$?"
echo "--- smoke: empty ---"
: > /tmp/t4; ./src/order.sh /tmp/t4; echo "rc=$?"
>"/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/slip/9cc6e438a87c88c6.$?"
