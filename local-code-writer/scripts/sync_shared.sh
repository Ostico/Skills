#!/bin/bash
# sync_shared.sh: compare the files that local-test-writer and local-code-writer share.
#
# The two skills keep their own copy of each shared file, so either one works alone. This
# script finds the other skill as the sibling folder of this skill's real folder (a skill
# installed as a link is followed) and compares each shared file with the sibling's copy.
#
# Usage:
#   bash sync_shared.sh               compare; print `same` or `DIFFERS` per file and the diffs
#   bash sync_shared.sh --take FILE   copy the sibling's FILE over this skill's copy
#
# Exit: 0 every shared file matches (or the sibling is missing: a `note:` line says so),
#       1 a shared file differs, 2 bad arguments or a FILE outside the shared list.
# The runners (run_aider_tests.sh, run_green.sh) differ by design: their diff is printed
# under its own heading and never changes the exit code.

SHARED="apply_blocks.py aider_entry.py ds4_server.sh follow_run.sh install_lmw_log.sh testnames.py lang/js.sh
  lang/php.sh sync_shared.sh"
RUNNERS="run_aider_tests.sh run_green.sh"

# The whole body is one { ...; } group: bash reads it before running any of it, so --take of
# this very file cannot break the run that copies it.
{

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SKILL_DIR=$(dirname "$SCRIPT_DIR")
case $(basename "$SKILL_DIR") in
  local-test-writer) SIBLING=local-code-writer ;;
  local-code-writer) SIBLING=local-test-writer ;;
  *) echo "sync_shared.sh: this skill folder is neither local-test-writer nor local-code-writer" >&2; exit 2 ;;
esac
OTHER=$(dirname "$SKILL_DIR")/$SIBLING/scripts

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 2; }

TAKE=
case $# in
  0) ;;
  2) [ "$1" = --take ] || usage; TAKE=$2 ;;
  *) usage ;;
esac

if [ ! -d "$OTHER" ]; then
  echo "note: $SIBLING not found; nothing to compare"
  exit 0
fi

if [ -n "$TAKE" ]; then
  case " $SHARED " in
    *" $TAKE "*) ;;
    *) echo "sync_shared.sh: $TAKE is not a shared file (shared: $SHARED)" >&2; exit 2 ;;
  esac
  [ -f "$OTHER/$TAKE" ] || { echo "sync_shared.sh: $SIBLING has no $TAKE" >&2; exit 2; }
  mkdir -p "$(dirname "$SCRIPT_DIR/$TAKE")"
  # A new file moved into place, so a script running from the old one keeps its own copy.
  cp -p "$OTHER/$TAKE" "$SCRIPT_DIR/$TAKE.take-tmp" && mv -f "$SCRIPT_DIR/$TAKE.take-tmp" "$SCRIPT_DIR/$TAKE"
  echo "took $TAKE from $SIBLING"
  exit 0
fi

rc=0 diffs=
for f in $SHARED; do
  if cmp -s "$SCRIPT_DIR/$f" "$OTHER/$f"; then
    echo "same     $f"
  else
    echo "DIFFERS  $f"
    rc=1
    diffs="$diffs $f"
  fi
done
for f in $diffs; do
  echo
  diff -u "$OTHER/$f" "$SCRIPT_DIR/$f" | sed "1s|^--- .*|--- $SIBLING/scripts/$f|;2s|^+++ .*|+++ $(basename "$SKILL_DIR")/scripts/$f|"
done

set -- $RUNNERS
a=$(dirname "$SKILL_DIR")/local-test-writer/scripts/$1
b=$(dirname "$SKILL_DIR")/local-code-writer/scripts/$2
echo
echo "runners (they differ by design; compare by hand)"
if [ -f "$a" ] && [ -f "$b" ]; then
  diff -u "$a" "$b"
else
  echo "  missing: $([ -f "$a" ] || echo "local-test-writer/scripts/$1 ")$([ -f "$b" ] || echo "local-code-writer/scripts/$2")"
fi
exit $rc
}
