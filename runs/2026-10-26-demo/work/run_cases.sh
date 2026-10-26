#!/bin/bash
# run_cases.sh [count] -- generate cases, run depsort, verify with check.awk.
count=${1:-300}
mkdir -p cases out
pass=0; fail=0
for ((i = 1; i <= count; i++)); do
  ./gen.sh "$i" > "cases/case_$i.gen"
  tail -n +2 "cases/case_$i.gen" > "cases/case_$i.in"
  ./depsort "cases/case_$i.in" > "out/case_$i.out" 2> "out/case_$i.err"
  st=$?
  why=$(awk -v status="$st" -f check.awk "cases/case_$i.in" "out/case_$i.out")
  hdr=$(head -1 "cases/case_$i.gen")
  if [[ -z $why ]]; then
    printf 'PASS case %3d  seed-header[%s] status=%d lines=%d\n' "$i" "$hdr" "$st" "$(wc -l < "out/case_$i.out")"
    pass=$((pass+1))
  else
    printf 'FAIL case %3d  seed-header[%s] status=%d :: %s\n' "$i" "$hdr" "$st" "$why"
    fail=$((fail+1))
  fi
done
echo
echo "TOTAL $count  PASS $pass  FAIL $fail"
[[ $fail -eq 0 ]]
