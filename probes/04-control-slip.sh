#!/bin/bash
# Branch D2f, the chosen design: the payload goes to its own file, and the control pipe
# carries only a slip {nonce, exit status, byte count}.  The chunk is head -c <bytes>.
# Run: bash probes/04-control-slip.sh      Healthy: the binary case reports a NUL count,
# the late writer is pinned out, and the following blocks are clean.
set -u
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
coproc INNER { exec setsid bash --norc --noprofile 2>/dev/null; }

run() {   # $1 body, $2 name
  local body=$1 nm=$2 nonce d t st sz raw="$dir/$2.raw" out="$dir/$2.chunk"
  nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n'); d="__HD_${nonce}__"
  printf "read -r -d '' __b <<'%s'\n%s\n%s\n" "$d" "$body" "$d" >&"${INNER[1]}"
  printf '%s' "eval -- \"\$__b\" >\"$raw\" 2>&1; __s=\$?; __n=\$(wc -c <\"$raw\"); printf 'SENT $nonce %d %d\x02' \"\$__s\" \"\$__n\"
" >&"${INNER[1]}"
  IFS= read -r -d $'\x02' t <&"${INNER[0]}"
  if [[ $t != "SENT $nonce "* ]]; then printf 'DESYNC     %s  [%q]\n' "$nm" "$t"; return; fi
  read -r st sz <<<"${t#SENT $nonce }"
  head -c "$sz" "$raw" >"$out"
  local nul; nul=$(( sz - $(tr -d '\0' <"$out" | wc -c) ))
  printf '%-22s status=%s bytes=%-8s lines=%-6s nul_bytes=%s\n' \
    "$nm" "$st" "$sz" "$(wc -l <"$out")" "$nul"
}

run 'echo hello; echo world'          plain
run 'for i in 1 2; do for c in $(seq 0 255); do printf "\\x$(printf %02x "$c")"; done; done' everybyte
run 'head -c 8388608 /dev/urandom'    urandom8m
run '{ sleep 0.6; echo LATE-OUTPUT; } & echo foreground' late
sleep 0.9
printf '%-22s file grew to %s bytes, chunk stays %s bytes\n' \
  'late (after the wait)' "$(wc -c <"$dir/late.raw")" "$(wc -c <"$dir/late.chunk")"
run 'exec 1>&2; echo moved'           exec1to2
run 'echo following block is clean'   following
run 'for i in $(seq 1 150); do echo line$i; done' lines150
printf '%-22s shown %s lines, first %s\n' 'lines150 tail -n 100' \
  "$(tail -n 100 "$dir/lines150.chunk" | wc -l)" "$(tail -n 100 "$dir/lines150.chunk" | head -1)"

echo '--- can a block reach the control channel by accident?'
run 'for f in /proc/$$/fd/*; do printf "%s->%s " "${f##*/}" "$(readlink "$f")"; done; echo' fds
printf '   %s\n' "$(tr '\n' ' ' < "$dir/fds.chunk")"
