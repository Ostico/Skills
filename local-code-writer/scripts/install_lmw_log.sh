#!/usr/bin/env bash
# install_lmw_log.sh: install `lmw-log`, the short command that follows the runs of
# local-test-writer and local-code-writer (it is this skill's scripts/follow_run.sh).
#
# Usage: bash install_lmw_log.sh
#
# Makes LMW_BIN_DIR/lmw-log (default ~/.local/bin/lmw-log) a link to the follow_run.sh next to
# this file, and says when that folder is not on PATH. A link already there is replaced (both
# skills' copies of follow_run.sh are the same); a file that is not a link is left alone.
# Exit: 0 installed, 1 a file that is not a link is in the way, 2 bad arguments.
set -euo pipefail

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 2; }
[ $# -eq 0 ] || usage

# The folder as it was called (no -P): a link through ~/.claude/skills keeps working when the
# skill's real folder moves.
SCRIPT_DIR=$(cd "$(dirname -- "$0")" && pwd)
BIN=${LMW_BIN_DIR:-$HOME/.local/bin}
LINK=$BIN/lmw-log

if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  echo "$LINK exists and is not a link: left as it is; remove it and run this again" >&2
  exit 1
fi
mkdir -p "$BIN"
ln -sfn "$SCRIPT_DIR/follow_run.sh" "$LINK"
echo "lmw-log -> $SCRIPT_DIR/follow_run.sh"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "note: $BIN is not on your PATH; add it (export PATH=\"$BIN:\$PATH\") or run $LINK" ;;
esac
