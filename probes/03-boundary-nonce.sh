#!/bin/bash
# Branch D2e, the runner-up: payload and boundary share one stream; the boundary is a
# one-byte terminator followed by a per-block random nonce.  Shown here because it works,
# and because its failure mode under D2d is what the nonce removes.
# Run: bash probes/03-boundary-nonce.sh      Healthy: every case says BYTE-EXACT.
set -u
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
coproc INNER { exec setsid bash --norc --noprofile 2>&1; }
DELIM=$'\x02'

run() {   # $1 body, $2 name -> writes $dir/$2.got
  local body=$1 nm=$2 nonce d t st= first=1
  local out="$dir/$2.got"
  nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
  d="__HD_${nonce}__"
  printf "read -r -d '' __b <<'%s'\n%s\n%s\n" "$d" "$body" "$d" >&"${INNER[1]}"
  printf "eval -- \"\$__b\" 2>&1; printf '\\\\x02SENT %s %%d\\\\x02' \$?\n" "$nonce" >&"${INNER[1]}"
  : >"$out"
  while IFS= read -r -d "$DELIM" t <&"${INNER[0]}"; do
    if [[ $t == "SENT $nonce "* ]]; then st=${t##* }; break; fi
    (( first )) || printf '%s' "$DELIM" >>"$out"
    printf '%s' "$t" >>"$out"; first=0
  done
  cmp -s "$dir/$nm.exp" "$out" \
    && printf 'BYTE-EXACT  %-42s status=%s bytes=%s\n' "$nm" "${st:-LOST}" "$(wc -c <"$out")" \
    || { printf 'MISMATCH    %s\n' "$nm"; od -c "$dir/$nm.exp" | head -3; od -c "$out" | head -3; }
}

printf 'plain text\nsecond line\n' > "$dir/plain.exp"
run 'echo plain text; echo second line' plain

printf 'a\x01b\x02SENT 0011223344556677 0\nc' > "$dir/nasty.exp"
run "printf 'a\\x01b\\x02SENT 0011223344556677 0\\nc'" nasty

printf 'no newline' > "$dir/tail.exp"
run "printf 'no newline'" tail

printf '' > "$dir/empty.exp"
run ':' empty

# the failure D2d ships with: a bare one-byte terminator splits the chunk
printf 'a\x01b\n' > "$dir/split.in"
{ IFS= read -r -d $'\x01' head1; IFS= read -r next1; } < "$dir/split.in"
printf 'D2d-split   same payload, bare \\x01 delimiter: this block got [%s], the next reader gets [%s]\n' "$head1" "$next1"
