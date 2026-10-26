#!/usr/bin/env bash
# check.sh CASE_FILE BIN -> one PASS/FAIL line.
set -u
casef=$1; bin=$2
out=$("$bin" "$casef" 2>&1); st=$?
declare -A needs=() seen=() color=() cnt=() pos=()
declare -a names=()
while read -r a b rest; do
  [ -n "${a:-}" ] && [ -n "${b:-}" ] || continue
  for x in "$a" "$b"; do [ -z "${seen[$x]:-}" ] && { seen[$x]=1; names+=("$x"); }; done
  needs[$a]="${needs[$a]:-} $b"
done < "$casef"
cyc=0
dfs() {
  local u=$1 d
  color[$u]=1
  for d in ${needs[$u]:-}; do
    case ${color[$d]:-0} in
      1) cyc=1; return 0 ;;
      0) dfs "$d"; [ $cyc = 1 ] && return 0 ;;
    esac
  done
  color[$u]=2; return 0
}
for nm in "${names[@]}"; do [ "${color[$nm]:-0}" = 0 ] && dfs "$nm"; [ $cyc = 1 ] && break; done

if [ $cyc = 1 ]; then
  [ $st -eq 1 ] || { echo "FAIL want-exit1 st=$st out=[$out]"; exit 0; }
  [[ $out == cycle:* ]] || { echo "FAIL want-cycle-prefix out=[$out]"; exit 0; }
  read -r _ cycnames <<< "$out"
  [ -n "${cycnames:-}" ] || { echo "FAIL empty-cycle-list"; exit 0; }
  declare -A inc=()
  for w in $cycnames; do inc[$w]=1; done
  # every consecutive pair (and last->first) must be a real "needs" edge
  set -- $cycnames
  first=$1; prev=$1; shift
  for w in "$@"; do
    case " ${needs[$prev]:-} " in *" $w "*) : ;; *) echo "FAIL cycle-edge $prev->$w list=[$cycnames]"; exit 0 ;; esac
    prev=$w
  done
  case " ${needs[$prev]:-} " in *" $first "*) : ;; *) echo "FAIL cycle-not-closed $prev->$first list=[$cycnames]"; exit 0 ;; esac
  echo "PASS cycle-valid"; exit 0
fi

[ $st -eq 0 ] || { echo "FAIL unexpected-exit st=$st out=[$out]"; exit 0; }
i=0
while read -r w; do
  [ -n "$w" ] || continue
  cnt[$w]=$(( ${cnt[$w]:-0} + 1 )); pos[$w]=$i; i=$((i+1))
done <<< "$out"
for nm in "${names[@]}"; do
  [ "${cnt[$nm]:-0}" = 1 ] || { echo "FAIL missing-or-dup [$nm] out=[$out]"; exit 0; }
done
for a in "${!needs[@]}"; do
  for b in ${needs[$a]}; do
    [ "$a" = "$b" ] && { echo "FAIL self-cycle-not-reported [$a]"; exit 0; }
    [ "${pos[$b]:-0}" -le "${pos[$a]:-0}" ] || { echo "FAIL order $a needs $b out=[$out]"; exit 0; }
  done
done
echo "PASS valid-order"
