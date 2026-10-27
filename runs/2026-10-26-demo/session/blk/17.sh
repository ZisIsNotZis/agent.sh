d=$(mktemp -d)
./src/suite.sh 400 > "$d/suite.log" 2>&1; rc=$?
echo "suite rc=$rc"; tail -3 "$d/suite.log"; echo "log=$d/suite.log"
grep -c fail "$d/suite.log" || true
>"/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/slip/9d402c85e3b8b2e4.$?"
