#!/usr/bin/env bash
# Create an Ollama variant of a model with a fixed context window and, optionally, its own
# sampling values, sharing the base weights.
# Usage: make_ctx_variant.sh <base-model> <num_ctx> [variant-name] [key=value ...]
# Each key=value becomes a PARAMETER line (e.g. temperature=0.7 top_p=0.8 presence_penalty=1.5);
# take them from the model card, for the thinking mode the runs will use.
# Default name: <base without tag>-<num_ctx/1024>k. Checks that RENDERER and PARSER (the chat and
# tool-call format) survive, since a variant without them talks to the model in the wrong format.
set -euo pipefail

BASE=${1:?usage: make_ctx_variant.sh <base-model> <num_ctx> [variant-name] [key=value ...]}
CTX=${2:?usage: make_ctx_variant.sh <base-model> <num_ctx> [variant-name] [key=value ...]}
shift 2
NAME=${BASE%%:*}-$((CTX / 1024))k
if [ $# -gt 0 ] && [[ $1 != *=* ]]; then NAME=$1; shift; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

{
  printf 'FROM %s\nPARAMETER num_ctx %s\n' "$BASE" "$CTX"
  for kv in "$@"; do
    [[ $kv == *=* ]] || { echo "not key=value: $kv" >&2; exit 2; }
    printf 'PARAMETER %s %s\n' "${kv%%=*}" "${kv#*=}"
  done
} > "$TMP/Modelfile"
ollama create "$NAME" -f "$TMP/Modelfile" > /dev/null

base_fmt=$(ollama show "$BASE" --modelfile | grep -E '^(RENDERER|PARSER|TEMPLATE)' || true)
new_fmt=$(ollama show "$NAME" --modelfile | grep -E '^(RENDERER|PARSER|TEMPLATE)' || true)
if [ "$base_fmt" != "$new_fmt" ]; then
  echo "ERROR: $NAME lost its chat format; base has:" >&2
  echo "$base_fmt" >&2
  exit 1
fi
echo "$NAME (num_ctx $CTX)"
ollama show "$NAME" --modelfile | grep '^PARAMETER'
