#!/usr/bin/env bash
# run.sh — the demo, regenerated: one unattended agent run against deepseek-flash.
# It costs metered tokens — 86k prompt tokens the run beside this file took —
# and it may be slow; everything it produces lands beside this file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

rm -rf "$here/session" "$here/work"
mkdir -p "$here/work"

cd "$here/work" || exit 1
bash "$root/agent.sh" \
  --task "$(cat "$here/task.txt")" \
  --session "$here/session" \
  --max-turns 26 \
  --compact-at 6000 \
  2>"$here/meter.log"

cp "$root/test/check-prefix.sh" "$here/check-prefix.sh"
cp "$here/session/traj.md" "$here/traj.md"
