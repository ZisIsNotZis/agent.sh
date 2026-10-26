#!/usr/bin/env bash
# test/stub-empty.sh — a model that says nothing on its first turn, then finishes.
set -u
n=$(($(cat "${AGENT_SH_SESSION:?}/stub.n" 2>/dev/null || printf 0) + 1))
printf '%s\n' "$n" >"$AGENT_SH_SESSION/stub.n"
case $n in
  1) reply='' ;;
  *) reply='# nothing left to run' ;;
esac
jq -n --arg c "$reply" '{
  choices: [{message: {role: "assistant", content: $c}}],
  usage: {prompt_tokens: 900, prompt_cache_hit_tokens: 800, prompt_cache_miss_tokens: 100, completion_tokens: 5}
}' >"$2"
