#!/usr/bin/env bash
# Collect everything a change-set dossier needs for a manual QA plan.
# Usage: collect_changes.sh <base-ref> [head-ref] [-o OUTDIR]
# Writes: OUTDIR/{commits.md,files.md,flags.md,stat.md,full.diff}
set -euo pipefail

BASE=${1:?usage: collect_changes.sh <base-ref> [head-ref] [-o OUTDIR]}
HEAD_REF=HEAD
OUT=./qa-dossier
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

# Two-dot: everything reachable from HEAD_REF that is not in BASE, as it stands now.
RANGE="$BASE..$HEAD_REF"
MERGE_BASE=$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null || echo "$BASE")

{
  echo "# Commits in $RANGE"
  echo
  echo "base:        $BASE ($(git rev-parse --short "$BASE"))"
  echo "head:        $HEAD_REF ($(git rev-parse --short "$HEAD_REF"))"
  echo "merge-base:  $(git rev-parse --short "$MERGE_BASE")"
  echo "commits:     $(git rev-list --count "$RANGE")"
  echo
  git log --no-merges --date=short --pretty='- %h %ad %an: %s' "$RANGE"
  echo
  echo "## Merge commits (PRs landed)"
  git log --merges --date=short --pretty='- %h %ad %s' "$RANGE" || true
  echo
  echo "## Reverts in range (behaviour may have gone back and forth)"
  git log --pretty='- %h %s' --grep='^Revert' -i "$RANGE" || true
} > "$OUT/commits.md"

{
  echo "# Changed files"
  echo
  echo '## Status (A=added M=modified D=deleted R=renamed)'
  echo '```'
  git diff --name-status -M "$MERGE_BASE" "$HEAD_REF"
  echo '```'
} > "$OUT/files.md"

{
  echo "# Change size"
  echo '```'
  git diff --stat -M "$MERGE_BASE" "$HEAD_REF"
  echo '```'
  echo
  echo "## Most-churned files (lines changed, descending)"
  echo '```'
  git diff --numstat -M "$MERGE_BASE" "$HEAD_REF" \
    | awk '$1 != "-" {print $1+$2"\t"$3}' | sort -rn | head -30
  echo '```'
} > "$OUT/stat.md"

# --- risk flags -------------------------------------------------------------
FILES=$(git diff --name-only -M "$MERGE_BASE" "$HEAD_REF")
MATCHED=$(mktemp)
trap 'rm -f "$MATCHED"' EXIT

flag() { # flag <heading> <grep-E pattern>
  local hits
  hits=$(printf '%s\n' "$FILES" | grep -Ei "$2" || true)
  [ -n "$hits" ] || return 0
  printf '%s\n' "$hits" >> "$MATCHED"
  echo "### $1"
  printf '%s\n' "$hits" | sed 's/^/- /'
  echo
}

{
  echo "# Risk flags"
  echo
  echo "Each section below is a category where a code change usually reaches the user."
  echo "An empty category is simply absent."
  echo
  flag "Database schema / migrations — data shape changed, may need a pre/post-deploy check" \
       '(^|/)(migrations?|db)/|migration|\.sql$'
  flag "Routes / controllers / public API — request or response contract may have moved" \
       'route|controller|(^|/)api/|endpoint|resource'
  flag "Authentication / authorisation / validation — who can do what may have changed" \
       'auth|permission|acl|polic|validator|credential|password|token|session|login'
  flag "Async workers / daemons / queues / cron — effects appear after a delay, not on click" \
       'worker|daemon|queue|cron|schedul|job|consumer|amq|kafka|rabbit'
  flag "Caching — stale data and first-vs-second request differences" \
       'cach|redis|memcach|invalidat'
  flag "Email / notifications / templates — messages users receive" \
       'mail|notif|template|smtp|webhook|push'
  flag "Frontend — anything visible on screen" \
       '\.(jsx?|tsx?|vue|svelte|s?css|less|html|twig|blade\.php)$'
  flag "Internationalisation — text shown in other languages" \
       'i18n|locale|lang|translat|\.po$|\.mo$|messages\.'
  flag "Configuration / feature flags / environment — behaviour may differ per environment" \
       '(^|/)config|\.env|\.ini$|\.neon$|\.ya?ml$|feature.?flag|toggle'
  flag "Dependencies — third-party behaviour may have shifted under us" \
       '(composer|package)\.(json|lock)$|yarn\.lock$|requirements.*\.txt$|Gemfile|go\.mod|\.csproj$'
  flag "File upload / export / import / conversion — format handling" \
       'upload|download|export|import|convert|parser?|xliff|csv|xlsx|pdf'
  flag "Money / billing / quota / limits" \
       'billing|payment|invoice|price|quota|limit|credit|subscription'
  flag "Submodules — pointer moved; the real change is inside the submodule" \
       '^(plugins|vendor|external|third_party)/'
  flag "Tests only — no manual test needed unless a test was DELETED (check status above)" \
       '(^|/)tests?/|(^|/)spec/|_test\.|\.test\.|\.spec\.'

  echo "### Uncategorised changed files — read these yourself, no heuristic covered them"
  UNMATCHED=$(printf '%s\n' "$FILES" | grep -vxF -f <(sort -u "$MATCHED") 2>/dev/null || printf '%s\n' "$FILES")
  if [ -n "$UNMATCHED" ]; then printf '%s\n' "$UNMATCHED" | sed 's/^/- /'; else echo "- (none)"; fi
  echo

  echo "### Deleted files (behaviour that may simply be gone)"
  git diff --name-status -M --diff-filter=D "$MERGE_BASE" "$HEAD_REF" | sed 's/^/- /'
  echo
  echo "### Renamed files (import paths and routes may have moved)"
  git diff --name-status -M --diff-filter=R "$MERGE_BASE" "$HEAD_REF" | sed 's/^/- /'
  echo
  echo "### Submodule pointer moves"
  git diff --submodule=short "$MERGE_BASE" "$HEAD_REF" | grep -E '^(Submodule|[+-]Subproject)' | sed 's/^/- /' || true
} > "$OUT/flags.md"

git diff -M "$MERGE_BASE" "$HEAD_REF" > "$OUT/full.diff"

echo "Dossier written to $OUT"
wc -l "$OUT"/*.md "$OUT/full.diff"
