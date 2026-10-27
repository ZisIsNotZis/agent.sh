d=$(mktemp -d); echo "dir=$d"
printf 'a b\nb c\n' > "$d/t1"
printf 'a b\nb c\nc a\n' > "$d/t2"
printf 'a a\n' > "$d/t3"
: > "$d/t4"
for f in t1 t2 t3 t4; do
  out=$(./src/order.sh < "$d/$f" 2>&1); rc=$?
  echo "--- $f rc=$rc"; echo "$out"
done
>"/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/slip/f03dc06a94bf69fe.$?"
