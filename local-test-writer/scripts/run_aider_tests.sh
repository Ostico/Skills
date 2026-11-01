#!/usr/bin/env bash
# Run aider with a local Ollama model to write tests, inside a guard that undoes anything it
# touched outside the files it was given.
#
# Usage:
#   run_aider_tests.sh --brief FILE --model NAME --num-ctx N --write PATH [--write PATH ...]
#                      [--read PATH ...] [--repo DIR] [--edit-format diff|whole]
#                      [--language English] [--map-tokens 0] [--timeout 1200] [--test-cmd CMD] [--test-dir DIR]
#                      [--out DIR]
#
# PATHs are relative to the repo root. NAME is the Ollama model (e.g. qwen3-coder-120k); the
# script talks to it as ollama_chat/NAME with num_ctx pinned, so Ollama never reloads it with a
# different window. Writes into OUT: aider's chat and LLM history, run.log, the guard's
# findings, the test output and report.md. Exit codes: 0 clean; 3 the guard undid edits outside
# --write; 4 suspected placeholder tests; 5 aider failed; 6 no test added; 124 timeout.
# aider answers in the system locale's language unless told otherwise; --language defaults to
# English. With --message-file aider sends one message and exits after the reply, so the brief
# must ask for the edits in that reply.
set -euo pipefail

usage() { sed -n '2,18p' "$0" >&2; exit 2; }

BRIEF='' MODEL='' NUM_CTX='' REPO='' LANGUAGE=English EDIT_FORMAT=diff MAP_TOKENS=0 TIMEOUT=1200
TEST_CMD='' TEST_DIR='' OUT=''
WRITE=() READ=()
while [ $# -gt 0 ]; do
  case $1 in
    --brief) BRIEF=$2; shift 2 ;;
    --model) MODEL=$2; shift 2 ;;
    --num-ctx) NUM_CTX=$2; shift 2 ;;
    --write) WRITE+=("$2"); shift 2 ;;
    --read) READ+=("$2"); shift 2 ;;
    --repo) REPO=$2; shift 2 ;;
    --edit-format) EDIT_FORMAT=$2; shift 2 ;;
    --language) LANGUAGE=$2; shift 2 ;;
    --map-tokens) MAP_TOKENS=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --test-cmd) TEST_CMD=$2; shift 2 ;;
    --test-dir) TEST_DIR=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$BRIEF" ] && [ -n "$MODEL" ] && [ -n "$NUM_CTX" ] && [ ${#WRITE[@]} -gt 0 ] || usage
BRIEF=$(cd "$(dirname "$BRIEF")" && pwd)/$(basename "$BRIEF")
REPO=$(git -C "${REPO:-.}" rev-parse --show-toplevel)
OUT=${OUT:-${TMPDIR:-/tmp}/ltw-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT/violations"
OUT=$(cd "$OUT" && pwd)
cd "$REPO"

ollama show "$MODEL" > /dev/null || { echo "model $MODEL not in ollama list" >&2; exit 2; }

# The guard can only restore files that were clean before the run.
for f in "${WRITE[@]}"; do
  if [ -n "$(git status --porcelain -- "$f")" ]; then
    echo "refusing: $f has uncommitted changes; commit or stash it first" >&2
    exit 2
  fi
done
git status --porcelain=v1 -uall > "$OUT/status-before.txt"
# Files already dirty keep the same status line when edited again, so hash their content too.
hash_dirty() { cut -c4- "$OUT/status-before.txt" | while IFS= read -r p; do
  [ -f "$p" ] && printf '%s  %s\n' "$(shasum -a 256 < "$p" | cut -c1-64)" "$p"; done; }
hash_dirty > "$OUT/dirty-before.sha"

# Model settings: pinned window, no cost, chat format through Ollama's own renderer.
cat > "$OUT/model-settings.yml" <<EOF
- name: ollama_chat/$MODEL
  edit_format: $EDIT_FORMAT
  use_repo_map: $([ "$MAP_TOKENS" = 0 ] && echo false || echo true)
  extra_params:
    num_ctx: $NUM_CTX
EOF
cat > "$OUT/model-metadata.json" <<EOF
{"ollama_chat/$MODEL": {"max_input_tokens": $NUM_CTX, "max_output_tokens": 16384,
  "input_cost_per_token": 0, "output_cost_per_token": 0,
  "litellm_provider": "ollama_chat", "mode": "chat"}}
EOF

args=(--model "ollama_chat/$MODEL" --model-settings-file "$OUT/model-settings.yml"
  --model-metadata-file "$OUT/model-metadata.json" --edit-format "$EDIT_FORMAT"
  --map-tokens "$MAP_TOKENS" --chat-language "$LANGUAGE" --message-file "$BRIEF" --yes-always
  --no-auto-commits --no-dirty-commits --no-gitignore --no-auto-lint --no-auto-test
  --no-suggest-shell-commands --no-detect-urls --no-restore-chat-history
  --analytics-disable --no-check-update --no-show-release-notes --no-fancy-input --no-pretty
  --chat-history-file "$OUT/chat.md" --input-history-file "$OUT/input.txt"
  --llm-history-file "$OUT/llm.txt")
for f in "${WRITE[@]}"; do args+=(--file "$f"); done
for f in ${READ[@]+"${READ[@]}"}; do args+=(--read "$f"); done

had_cache=$([ -e .aider.tags.cache.v4 ] && echo yes || echo no)
start=$(date +%s)
set +e
OLLAMA_API_BASE=${OLLAMA_API_BASE:-http://127.0.0.1:11434} \
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$TIMEOUT" aider "${args[@]}" > "$OUT/run.log" 2>&1
rc=$?
set -e
secs=$(( $(date +%s) - start ))
[ "$had_cache" = no ] && rm -rf .aider.tags.cache.v4

# Guard: every path that changed and is not in --write is undone (and kept in OUT/violations).
git status --porcelain=v1 -uall > "$OUT/status-after.txt"
violations=0
while IFS= read -r line; do
  path=${line:3}
  allowed=no
  for f in "${WRITE[@]}"; do [ "$path" = "$f" ] && allowed=yes; done
  [ $allowed = yes ] && continue
  violations=$((violations + 1))
  mkdir -p "$OUT/violations/$(dirname "$path")"
  if grep -q -- " $path\$" "$OUT/status-before.txt"; then
    echo "UNRESTORED (was already dirty before the run): $path" >> "$OUT/guard.txt"
  elif [ "${line:0:2}" = '??' ]; then
    mv "$path" "$OUT/violations/$path"
    echo "removed new file: $path" >> "$OUT/guard.txt"
  else
    git diff -- "$path" > "$OUT/violations/$path.diff"
    git checkout -- "$path"
    echo "reverted: $path" >> "$OUT/guard.txt"
  fi
done < <(comm -13 <(sort "$OUT/status-before.txt") <(sort "$OUT/status-after.txt"))

hash_dirty > "$OUT/dirty-after.sha"
while IFS= read -r line; do
  path=${line:66}
  echo "UNRESTORED (was already dirty before the run, then changed): $path" >> "$OUT/guard.txt"
  violations=$((violations + 1))
done < <(comm -13 <(sort "$OUT/dirty-before.sha") <(sort "$OUT/dirty-after.sha"))

# Placeholder scan over the added lines of the allowed files.
git diff -- "${WRITE[@]}" > "$OUT/tests.diff"
grep -n -i -E '^\+.*(not implemented|todo|fixme|\.skip\(|\.todo\(|expect\(true\)|placeholder)' \
  "$OUT/tests.diff" > "$OUT/placeholders.txt" || true
added_tests=$(grep -c -E '^\+\s*(test|it)(\.each\(.*\))?\(' "$OUT/tests.diff" || true)

test_rc=''
if [ -n "$TEST_CMD" ]; then
  set +e
  (cd "${TEST_DIR:-$REPO}" && perl -e 'alarm shift; exec @ARGV' 600 sh -c "$TEST_CMD") > "$OUT/test-output.txt" 2>&1
  test_rc=$?
  set -e
fi

{
  echo "# local-test-writer run"
  echo
  echo "- model: $MODEL (num_ctx $NUM_CTX), edit format $EDIT_FORMAT, repo map tokens $MAP_TOKENS"
  echo "- aider exit: $rc, time: ${secs}s (timeout ${TIMEOUT}s)"
  echo "- tests added (test/it lines): $added_tests"
  echo "- guard: $( [ -s "$OUT/guard.txt" ] && cat "$OUT/guard.txt" | tr '\n' ';' || echo 'no edits outside --write')"
  echo "- suspected placeholders: $(wc -l < "$OUT/placeholders.txt" | tr -d ' ')"
  [ -n "$test_rc" ] && echo "- test command exit: $test_rc (output in test-output.txt)"
  echo
  echo "Read tests.diff yourself before trusting any of this: the guard and the scan catch the"
  echo "obvious failures, not a weak assertion."
} > "$OUT/report.md"
cat "$OUT/report.md"
echo "out: $OUT"

[ $rc -eq 142 ] && exit 124
[ $violations -gt 0 ] && [ -s "$OUT/guard.txt" ] && exit 3
[ -s "$OUT/placeholders.txt" ] && exit 4
[ $rc -ne 0 ] && exit 5
[ "$added_tests" -eq 0 ] && exit 6
exit 0
