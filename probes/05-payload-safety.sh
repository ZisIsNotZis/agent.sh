#!/bin/bash
# Branch D5: bash has no binary-to-escaped mode, and the things that look like one are traps.
# Run: bash probes/05-payload-safety.sh      Healthy: the UTF-8 line survives, the NUL/ESC
# line is *not* caught by iconv, and jq escapes NUL without failing.
set -u
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT

printf 'h\xc3\xa9llo \xe2\x80\x94 \xe4\xb8\xad\xe6\x96\x87 \xe2\x9c\x93\n' > "$dir/utf8"
printf 'a\0b\033[31mred\n' > "$dir/mixed"
printf '\377\376\000A' > "$dir/broken"
printf '' > "$dir/empty"

echo '--- cat -v destroys valid UTF-8, so it is never a sanitiser'
printf 'orig:     %s\n' "$(cat "$dir/utf8")"
printf 'cat -v:   %s\n' "$(cat -v "$dir/utf8")"
case "$(cat -v "$dir/utf8")" in
  *'M-CM-'*) echo 'TRAP      cat -v mangled it';;
  *)          echo 'UNEXPECTED cat -v left it alone';;
esac

echo
echo '--- iconv validity alone is not a binary test'
iconv -f UTF-8 -t UTF-8 < "$dir/mixed" >/dev/null 2>&1 \
  && echo "TRAP      'a<NUL>b<ESC>[31m' is *valid* UTF-8 (NUL and ESC are legal)" \
  || echo 'UNEXPECTED mixed was rejected'
iconv -f UTF-8 -t UTF-8 < "$dir/broken" >/dev/null 2>&1 \
  && echo 'UNEXPECTED broken was accepted' \
  || echo 'GOOD      a stray 0xFF/0xFE is rejected'

echo
echo '--- the detector that works: NUL present, or iconv rejects the file'
printf 'mixed  nul_bytes=%s\n' "$(( $(wc -c < "$dir/mixed") - $(tr -d '\0' < "$dir/mixed" | wc -c) ))"
printf 'utf8   nul_bytes=%s\n' "$(( $(wc -c < "$dir/utf8")  - $(tr -d '\0' < "$dir/utf8"  | wc -c) ))"

echo
echo '--- tr --print is byte-based and flags valid UTF-8, so it is not a detector'
printf 'utf8  "non-printable" bytes per tr: %s (it should be 0)\n' \
  "$(LC_ALL=C tr -d '[:print:][:space:]' < "$dir/utf8" | wc -c)"

echo
echo '--- jq -Rs reads raw bytes from a FILE and always emits valid JSON'
jq -Rs . < "$dir/mixed"
jq -Rs . < "$dir/broken"
jq -Rs . < "$dir/empty"
jq -e . < <(jq -Rs . < "$dir/mixed") >/dev/null && echo 'GOOD      the result parses'

echo
echo '--- never route payload through a bash variable: NUL is dropped silently'
jq -n --arg s "$(cat "$dir/mixed")" '{"c": $s}' 2>/dev/null

echo
echo '--- what auto-escaping costs: 3 MB of /dev/urandom'
head -c 3000000 /dev/urandom > "$dir/rnd"
t0=$SECONDS
jq -Rs . < "$dir/rnd" > "$dir/rnd.json"
rc=$?
printf 'in=%s bytes out=%s bytes rc=%s time=%ss\n' "$(wc -c < "$dir/rnd")" "$(wc -c < "$dir/rnd.json")" "$rc" "$((SECONDS - t0))"
jq -e . < "$dir/rnd.json" >/dev/null && echo 'GOOD      valid JSON, and it is 2.4x the input'
