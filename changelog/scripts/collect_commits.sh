#!/usr/bin/env bash
# Collect everything a changelog needs from a commit range, pre-sorted by change type.
# Usage: collect_commits.sh <base-ref> [head-ref] [-o OUTDIR]
# Writes: OUTDIR/{range.md,by-type.md,breaking.md,unclassified.md,contributors.md}
set -euo pipefail

BASE=${1:?usage: collect_commits.sh <base-ref> [head-ref] [-o OUTDIR]}
HEAD_REF=HEAD
OUT=./changelog-dossier
shift
while [ $# -gt 0 ]; do
  case $1 in
    -o|--out) OUT=$2; shift 2 ;;
    *) HEAD_REF=$1; shift ;;
  esac
done

git rev-parse --verify -q "$BASE" >/dev/null || { echo "unknown base ref: $BASE" >&2; exit 2; }
git rev-parse --verify -q "$HEAD_REF" >/dev/null || { echo "unknown head ref: $HEAD_REF" >&2; exit 2; }
mkdir -p "$OUT"

RANGE="$BASE..$HEAD_REF"
MERGE_BASE=$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null || echo "$BASE")

# Conventional-commit types, mapped to the changelog categories the template uses.
# Anything not matching lands in unclassified.md and must be read by hand.
types_added='feat'
types_fixed='fix'
types_changed='perf|refactor|style'
types_removed='revert'
types_security='security'
types_deprecated='deprecate'
types_internal='chore|build|ci|test|docs'

log_type() { # $1 = regex of types
  git log --no-merges --date=short --pretty='%h|%ad|%an|%s' "$RANGE" \
    | awk -F'|' -v re="^($1)(\\(.*\\))?!?:" '$4 ~ re'
}

{
  echo "# Range"
  echo
  echo "base:        $BASE ($(git rev-parse --short "$BASE"))"
  echo "head:        $HEAD_REF ($(git rev-parse --short "$HEAD_REF"))"
  echo "merge-base:  $(git rev-parse --short "$MERGE_BASE")"
  echo "commits:     $(git rev-list --count "$RANGE")"
  echo "first date:  $(git log --reverse --date=short --pretty=%ad "$RANGE" | head -1)"
  echo "last date:   $(git log -1 --date=short --pretty=%ad "$HEAD_REF")"
  echo
  echo "## Tags in range (candidate version numbers)"
  git tag --contains "$MERGE_BASE" --sort=-creatordate 2>/dev/null | head -20 || true
  echo
  echo "## Nearest tag before base"
  git describe --tags --abbrev=0 "$BASE" 2>/dev/null || echo "(none - repository may be untagged)"
  echo
  echo "## Merge commits (pull requests landed)"
  git log --merges --date=short --pretty='- %h %ad %s' "$RANGE" || true
} > "$OUT/range.md"

{
  echo "# Commits by type"
  echo
  echo "Each line is: sha|date|author|subject"
  for pair in \
    "Added:$types_added" \
    "Fixed:$types_fixed" \
    "Changed:$types_changed" \
    "Removed:$types_removed" \
    "Security:$types_security" \
    "Deprecated:$types_deprecated" \
    "Internal:$types_internal"
  do
    label=${pair%%:*}; re=${pair#*:}
    echo
    echo "## $label  (matched: $re)"
    out=$(log_type "$re" || true)
    if [ -n "$out" ]; then echo "$out"; else echo "(none)"; fi
  done
} > "$OUT/by-type.md"

{
  echo "# Breaking changes"
  echo
  echo "State these plainly in the changelog; never hide a break behind vague wording."
  echo
  echo '## Subject carries a "!" before the colon'
  git log --no-merges --date=short --pretty='- %h %ad %s' "$RANGE" \
    | grep -E '^- [0-9a-f]+ [0-9-]+ [a-z]+(\(.*\))?!:' || echo "(none)"
  echo
  echo "## Body or subject mentions BREAKING CHANGE"
  git log --no-merges --date=short --pretty='- %h %ad %s' --grep='BREAKING' -i "$RANGE" || true
  echo
  echo "## Reverts (behaviour may have gone back and forth)"
  git log --no-merges --pretty='- %h %s' --grep='^Revert' -i "$RANGE" || true
} > "$OUT/breaking.md"

{
  echo "# Unclassified commits"
  echo
  echo "No conventional-commit prefix matched. Read each one and place it by hand -"
  echo "an unclassified commit left out of the changelog is a silent omission."
  echo
  all_types="$types_added|$types_fixed|$types_changed|$types_removed|$types_security|$types_deprecated|$types_internal"
  out=$(git log --no-merges --date=short --pretty='%h|%ad|%an|%s' "$RANGE" \
        | awk -F'|' -v re="^($all_types)(\\(.*\\))?!?:" '$4 !~ re' || true)
  if [ -n "$out" ]; then echo "$out"; else echo "(none - every commit matched a known type)"; fi
} > "$OUT/unclassified.md"

{
  echo "# Contributors"
  echo
  git shortlog -sne --no-merges "$RANGE" || true
} > "$OUT/contributors.md"

echo "wrote dossier to $OUT:"
for f in range.md by-type.md breaking.md unclassified.md contributors.md; do
  printf '  %-18s %s lines\n' "$f" "$(wc -l < "$OUT/$f" | tr -d ' ')"
done
