#!/usr/bin/env bash
# gen.sh SEED -> random case on stdout. Mostly acyclic (edges follow a hidden random
# order); ~1 in 4 seeds get a deliberately injected cycle. Includes repeats and
# right-only/left-only packages.
set -u
RANDOM=$1
n=$(( RANDOM % 8 + 2 ))                       # 2..9 packages
TOP=5                                          # packages live in a window of 5 names
declare -a ord=()
# hidden order: shuffled list of distinct names
declare -a pool=()
for ((i=0;i<TOP;i++)); do pool+=("pk$i"); done
for ((i=TOP-1;i>0;i--)); do j=$(( RANDOM % (i+1) )); t=${pool[$i]}; pool[$i]=${pool[$j]}; pool[$j]=$t; done
for ((i=0;i<n;i++)); do ord+=("${pool[$((i % TOP))]}"); done
m=$(( RANDOM % (n*2) ))
for ((k=0;k<m;k++)); do
  a=${ord[$((RANDOM % n))]}; b=${ord[$((RANDOM % n))]}
  echo "$a $b"                                 # may be forwards (needs) or backwards
done
# repeats of an earlier line, sometimes
if (( RANDOM % 3 == 0 )); then
  a=${ord[$((RANDOM % n))]}; b=${ord[$((RANDOM % n))]}
  echo "$a $b"; echo "$a $b"
fi
if (( RANDOM % 4 == 0 )); then
  len=$(( RANDOM % 3 + 2 ))
  declare -a c=()
  for ((i=0;i<len;i++)); do c+=("${pool[$(( RANDOM % TOP ))]}"); done
  for ((i=0;i<len;i++)); do echo "${c[$i]} ${c[$(((i+1)%len))]}"; done
fi
