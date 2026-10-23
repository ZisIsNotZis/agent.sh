#!/bin/bash
# Branch D1b: one shell, its own stdio hijacked to a capture file, eval in the same shell.
# Run: bash probes/02-single-shell.sh
# Healthy (that is, the claim): the state lines print, then `set -e` ends the harness —
# "UNREACHABLE" must NOT print, and the script exits non-zero.
set -u
cap=$(mktemp); trap 'rm -f "$cap"' EXIT
exec {out}>&1 {inp}<&0

block() {                       # $1 = the text the model wrote
  local b=$1 st
  exec >"$cap" 2>&1 </dev/null  # `>` truncates AND resets the offset; `: >` would leave a NUL hole
  eval -- "$b"
  st=$?
  exec 1>&$out 2>&$out
  cat -- "$cap"
  printf '[status %d]\n' "$st"
}

echo '--- the happy path: this half really does work'
block 'echo hello; echo world'
block 'cd /tmp && V=7'
block 'echo "state persisted: pwd=$PWD V=$V"'
block 'exec 1>/dev/null; echo invisible'
block 'echo "recovered after the block closed fd 1"'
block 'read -r x < /dev/stdin && echo "stdin was a tty" || echo "stdin is not a tty"'

echo
echo '--- the next block is what a careful model writes: set -euo pipefail and a failing'
echo '    command.  It kills this shell, so nothing below it runs: expect the probe to'
echo '    stop here, with no [status] line and a non-zero exit code.'
block 'set -euo pipefail; echo before-fail; false; echo after-fail'
echo 'UNREACHABLE  the harness survived set -e'
echo
echo 'The shell running this probe is the shell the block ran in, so the block ended the'
echo 'probe itself, mid-block, with its output lost.  That is branch D1b losing, and it is'
echo 'why the design puts the eval in a child shell it is allowed to restart.'
