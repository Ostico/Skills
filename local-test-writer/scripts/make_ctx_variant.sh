#!/usr/bin/env bash
# Create an Ollama variant of a model with a fixed context window, sharing the base weights.
# Usage: make_ctx_variant.sh <base-model> <num_ctx> [variant-name]
# Default name: <base without tag>-<num_ctx/1024>k. Checks that RENDERER and PARSER (the chat and
# tool-call format) survive, since a variant without them talks to the model in the wrong format.
set -euo pipefail

BASE=${1:?usage: make_ctx_variant.sh <base-model> <num_ctx> [variant-name]}
CTX=${2:?usage: make_ctx_variant.sh <base-model> <num_ctx> [variant-name]}
NAME=${3:-${BASE%%:*}-$((CTX / 1024))k}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'FROM %s\nPARAMETER num_ctx %s\n' "$BASE" "$CTX" > "$TMP/Modelfile"
ollama create "$NAME" -f "$TMP/Modelfile" > /dev/null

base_fmt=$(ollama show "$BASE" --modelfile | grep -E '^(RENDERER|PARSER|TEMPLATE)' || true)
new_fmt=$(ollama show "$NAME" --modelfile | grep -E '^(RENDERER|PARSER|TEMPLATE)' || true)
if [ "$base_fmt" != "$new_fmt" ]; then
  echo "ERROR: $NAME lost its chat format; base has:" >&2
  echo "$base_fmt" >&2
  exit 1
fi
echo "$NAME (num_ctx $CTX)"
