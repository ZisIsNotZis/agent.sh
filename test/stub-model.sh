#!/usr/bin/env bash
# test/stub-model.sh — a model in a file: $1 is the request, $2 is where the response goes.
# It answers as `deepseek-flash` would be asked to: each turn's content IS a bash block.
# The usage block is fabricated, so a test can check the meter without spending a token.
set -u
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

jq -n --arg c "$reply" --argjson n "$n" '{
  choices: [{message: {role: "assistant", content: $c}}],
  usage: {
    prompt_tokens: (1200 * $n),
    prompt_cache_hit_tokens: (1024 * ($n - 1)),
    prompt_cache_miss_tokens: (1200 * $n - 1024 * ($n - 1)),
    completion_tokens: 40
  }
}' >"$2"
