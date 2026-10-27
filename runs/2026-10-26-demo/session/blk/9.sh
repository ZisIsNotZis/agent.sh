cat /home/z/vibe/agent.sh/runs/2026-10-26-demo/session/jobs/1/log
echo "=== report tail ==="
tail -3 report.txt
echo "=== non-FAIL lines ==="
grep -v FAIL report.txt | head -20
>"/home/z/vibe/agent.sh/runs/2026-10-26-demo/session/slip/8f8997a1b054d9d7.$?"
