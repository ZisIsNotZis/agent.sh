#!/usr/bin/env bash
# test/stub-model.sh — a model in a file: $1 is the request, $2 is where the response goes.
# It answers as `deepseek-flash` would be asked to: each turn's content IS a bash block.
# The usage block is fabricated, so a test can check the meter without spending a token.
set -u

last=$(jq -r '.messages[-1].content' "$1")
if [[ $last == 'User: /compact'* ]]; then
  len=$(jq '.messages | length' "$1")
  jq -n --arg c 'the stub summary: a list was made in one turn, a job was started and reaped' \
    --argjson pt $((1000 * len)) '{
    choices: [{message: {role: "assistant", content: $c}}],
    usage: {prompt_tokens: $pt, prompt_cache_hit_tokens: ($pt - 200), prompt_cache_miss_tokens: 200, completion_tokens: 30}
  }' >"$2"
  exit 0
fi

n=$(($(cat "${AGENT_SH_SESSION:?}/stub.n" 2>/dev/null || printf 0) + 1))
printf '%s\n' "$n" >"$AGENT_SH_SESSION/stub.n"

case $n in
  1) reply='# turn one: prove the shell answers, and start something slow
echo hello from turn one
bgrun -n "the stub job" sh -c "sleep 0.2; echo from the stub job"' ;;
  2) reply='# turn two: the job has finished, so read what it wrote
cat "$AGENT_SH_JOBS/1/log"' ;;
  *) reply='# done' ;;
esac

# the meter is deterministic and shaped like the real one: it grows by one appended pair,
# and every request repeats the previous prompt as a prefix
len=$(jq '.messages | length' "$1")
pt=$((1000 * len))
jq -n --arg c "$reply" --argjson pt "$pt" '{
  choices: [{message: {role: "assistant", content: $c}}],
  usage: {
    prompt_tokens: $pt,
    prompt_cache_hit_tokens: (if $pt > 200 then $pt - 200 else 0 end),
    prompt_cache_miss_tokens: (if $pt > 200 then 200 else $pt end),
    completion_tokens: 40
  }
}' >"$2"
