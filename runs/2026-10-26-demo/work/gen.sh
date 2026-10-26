#!/bin/bash
# gen.sh <seed> -- print one random case: header line "N M CYC" then M pairs.
# CYC=1 means the case is built around a deliberate cycle.
seed=$1
RANDOM=$seed
n=$(( RANDOM % 7 + 2 ))          # distinct packages, 2..8 (2 needed for forced cycle)
m=$(( RANDOM % 9 + 1 ))          # pair lines
cyc=$(( RANDOM % 4 == 0 ? 1 : 0 ))
echo "$n $m $cyc"
declare -a names
for ((i=0;i<n;i++)); do names[i]="p$i"; done
for ((i=0;i<m;i++)); do
  a=${names[RANDOM % n]}; b=${names[RANDOM % n]}
  echo "$a $b"
done
if (( cyc )); then
  # append a guaranteed 2-cycle (may duplicate existing lines: that's fine)
  echo "${names[0]} ${names[1]}"
  echo "${names[1]} ${names[0]}"
fi
