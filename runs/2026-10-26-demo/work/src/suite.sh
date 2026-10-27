#!/usr/bin/env bash
# suite.sh [count] — generate graphs, run order.sh on each, and check it independently.
# One line per case; the last line is the summary. Exit 0 only if every case passed.
set -u
count=${1:-40}
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
pass=0; fail=0; seed=20261026

gen() {   # $1 = case number; writes "$work/g" and "$work/expect"
  local n=$1 i k a b
  seed=$(( (seed * 1103515245 + 12345) % 2147483648 )); k=$(( seed % 7 + 2 ))
  : >"$work/g"
  for ((i = 0; i < k; i++)); do
    seed=$(( (seed * 1103515245 + 12345) % 2147483648 )); a=$(( seed % 5 + 1 ))
    seed=$(( (seed * 1103515245 + 12345) % 2147483648 )); b=$(( seed % 5 + 1 ))
    ((a == b)) && b=$(( b % 5 + 1 ))
    echo "p$a p$b" >>"$work/g"
  done
}

check() {  # $1 = the case number; 0 when the order is valid, 1 when not
  local i line prev='' seen=' ' x y order
  order=$("$here/order.sh" "$work/g"); local rc=$?
  # cycle detection, independent of order.sh: does the input contain one?
  local cyc=0
  awk '{ print $1, $2 }' "$work/g" | sort -u | while read -r x y; do :; done
  if [[ -n $(awk 'BEGIN{c=0} {e[$1,"",$2]=1} END{exit 0}' /dev/null) ]]; then :; fi
  # a small DFS over the input, on the pair list itself
  cyc=$(awk '
    { e[$1 SUBSEP $2] = 1; n[$1] = 1; n[$2] = 1 }
    END {
      for (s in n) {
        depth = 0
        # iterative DFS with colouring
      }
      # colour map
      for (v in n) col[v] = 0
      for (s in n) if (col[s] == 0 && dfs(s)) { print 1; exit }
      print 0
    }
    function dfs(u,   v, key) {
      col[u] = 1
      for (v in n) {
        key = u SUBSEP v
        if (!(key in e)) continue
        if (col[v] == 1) return 1
        if (col[v] == 0 && dfs(v)) return 1
      }
      col[u] = 2
      return 0
    }' "$work/g")
  if [[ $cyc == 1 ]]; then
    [[ $rc == 1 && $order == cycle:* ]] && return 0 || return 1
  fi
  ((rc == 0)) || return 1
  # every package once, and every dependency before the package that needs it
  local -A pos=()
  i=0
  while read -r line; do pos[$line]=$i; i=$((i + 1)); done <<<"$order"
  while read -r x y; do
    [[ -n ${pos[$x]-} && -n ${pos[$y]-} ]] || return 1
    ((pos[$y] < pos[$x])) || return 1    # y is a dependency of x, so y comes first
  done <"$work/g"
  [[ $i == $(awk '{ print $1; print $2 }' "$work/g" | sort -u | wc -l) ]] || return 1
  return 0
}

for ((n = 1; n <= count; n++)); do
  gen "$n"
  if check "$n"; then
    pass=$((pass + 1)); printf 'case %03d PASS\n' "$n"
  else
    fail=$((fail + 1)); printf 'case %03d FAIL  %s\n' "$n" "$(tr '\n' ' ' <"$work/g")"
  fi
done
printf 'SUMMARY total=%d pass=%d fail=%d\n' "$count" "$pass" "$fail"
((fail == 0))
