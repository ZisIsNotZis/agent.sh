#!/bin/bash
# What a bash primitive actually does, where a guess would have been made.
# Run: bash probes/01-read-semantics.sh     Healthy: every line says EXPECTED.
set -u
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ok() { printf 'EXPECTED  %s\n' "$*"; }
bad() { printf 'UNEXPECTED %s\n' "$*"; }

echo '--- read is delimiter-seeking, not "whatever is available"'
printf 'a\nb\n' > "$tmp/two"
{ read -r l1; read -r l2; } < "$tmp/two"
[ "$l1/$l2" = "a/b" ] && ok "two reads on a file return the two lines" || bad "got [$l1/$l2]"

echo '--- read -d takes one byte, the first character of its argument'
printf 'helloXabYX' > "$tmp/d"
IFS= read -r -d "ab" got < "$tmp/d"
[ "$got" = "helloX" ] && ok "-d \"ab\" stopped at the first 'a', not at \"ab\"" || bad "got [$got]"

echo '--- a timed read returns partial input, status 142 (128+SIGALRM)'
mkfifo "$tmp/f"; exec 3<>"$tmp/f"
printf 'half-a-line' >&3
IFS= read -r -t 0.3 -u 3 part; st=$?
[ "$st" -gt 128 ] && [ "$part" = "half-a-line" ] && ok "status $st with partial [$part]" || bad "status $st part [$part]"
exec 3<&- 3>&-

echo '--- printf %q cannot transport arbitrary text (bash rejects \\\" outside quotes)'
want="echo it's fine"
quoted=$(printf %q "$want")
got=$(eval -- "$quoted" 2>&1); st=$?
if [ "$got" = "$want" ] && [ "$st" = 0 ]; then bad "%q round-tripped, unexpectedly"
else ok "%q did not round-trip: eval gave status $st and [${got:0:40}] from [${quoted:0:40}]"; fi

echo '--- a non-interactive bash never prints a job notice on its own'
out=$(bash --norc -c 'sleep 0.2 & sleep 0.6' 2>&1)
[ -z "$out" ] && ok "silence: nothing is printed when the job finishes" || bad "got [$out]"

echo '--- wait -n -p names the child that finished, in completion order'
out=$(bash --norc -c 'sleep 0.5 & p1=$!; sleep 0.2 & p2=$!; wait -n -p g; echo "$g $?"; wait -n -p g; echo "$g $?"; wait -n -p g; echo "empty $?"')
first=$(echo "$out" | sed -n 1p); second=$(echo "$out" | sed -n 2p); third=$(echo "$out" | sed -n 3p)
case "$first" in *" 0") ok "first finished was the shorter sleep: $first";; *) bad "$first";; esac
case "$second" in *" 0") ok "then the longer one: $second";; *) bad "$second";; esac
[ "$third" = "empty 127" ] && ok "127 means nothing is pending" || bad "$third"

echo '--- bash version this depends on'
printf 'INFO      %s (need >= 5.1 for wait -n -p)\n' "$BASH_VERSION"
