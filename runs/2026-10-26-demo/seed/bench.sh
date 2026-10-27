#!/usr/bin/env bash
# bench.sh — a slow measurement, so it has to be started with bgrun and reaped by the harness.
set -u
edges=${1:-400}
start=$(date +%s%N)
awk -v n="$edges" 'BEGIN {
  seed = 7; for (i = 0; i < n; i++) { seed = (seed * 1103515245 + 12345) % 2147483648; a = seed % 997
    seed = (seed * 1103515245 + 12345) % 2147483648; b = seed % 997
    if (a != b) print "p" a, "p" b }
}' >/tmp/bench_$$.txt
sleep 120
lines=$(wc -l </tmp/bench_$$.txt); rm -f /tmp/bench_$$.txt
end=$(date +%s%N)
printf 'bench: %s edges generated, wall %s ms, %.1f edges/ms\n' \
  "$lines" "$(( (end - start) / 1000000 ))" "$(awk -v l="$lines" -v ms="$(( (end-start)/1000000 ))" 'BEGIN{printf "%.1f", l/ms}')"
