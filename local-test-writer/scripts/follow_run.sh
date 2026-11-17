#!/usr/bin/env bash
# Follow a run of local-test-writer or local-code-writer while it works: the step under way, the
# model's reply as it streams (run.log), and report.md once the run ends. Ctrl-C stops
# following, not the run.
#
# Usage:
#   follow_run.sh            follow the latest run of either skill
#   follow_run.sh OUT-DIR    follow that run
#   follow_run.sh --list     the last runs of both skills, one start and one end line each
#   follow_run.sh --path     the full path of the latest run's log (run.log)
#
# Each skill's runner writes its runs under its own state folder,
# ${XDG_STATE_HOME:-~/.local/state}/local-test-writer or .../local-code-writer, with a link
# `current` to its latest run; the latest run is the one started last. With LTW_STATE_DIR set,
# only that folder is read. One short command serves both skills (the two copies of this file
# are the same), installed by install_lmw_log.sh next to this file:
#   bash ~/.claude/skills/<skill>/scripts/install_lmw_log.sh
set -euo pipefail

# The whole body is one { ...; } group: bash reads it before running any of it, so a new copy
# of this file (sync_shared.sh) cannot break a follow under way.
{
if [ -n "${LTW_STATE_DIR:-}" ]; then
  STATES=("$LTW_STATE_DIR")
else
  base=${XDG_STATE_HOME:-$HOME/.local/state}
  STATES=("$base/local-test-writer" "$base/local-code-writer")
fi
# The latest run: of each folder's `current`, the one whose pid file (written at the start) is
# newest.
latest() {
  local s best=''
  for s in "${STATES[@]}"; do
    [ -e "$s/current" ] || continue
    if [ -z "$best" ] || [ "$s/current/pid" -nt "$best/pid" ]; then best=$s/current; fi
  done
  [ -n "$best" ] && echo "$best"
}
case ${1:-} in
  -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 2 ;;
  --list)
    runs=$(for s in "${STATES[@]}"; do
      if [ -f "$s/runs.tsv" ]; then sed "s|^|$(basename "$s")	|" "$s/runs.tsv"; fi
    done | sort -t '	' -k 2,2 -s | tail -n 20)
    if [ -n "$runs" ]; then echo "$runs"; else echo "no runs in ${STATES[*]}"; fi
    exit 0 ;;
  --path)
    cur=$(latest) || { echo "no run yet in ${STATES[*]}" >&2; exit 2; }
    echo "$(cd "$cur" && pwd -P)/run.log"; exit 0 ;;
esac
OUT=${1:-$(latest || true)}
[ -n "$OUT" ] && [ -d "$OUT" ] || { echo "no run at ${OUT:-${STATES[*]}}" >&2; exit 2; }
OUT=$(cd "$OUT" && pwd -P)

stage() { cat "$OUT/stage" 2>/dev/null || echo unknown; }
# Running: the pid is alive and the stage is not "done" (a reused pid of a dead run is not).
running() {
  local pid
  pid=$(cat "$OUT/pid" 2>/dev/null) || return 1
  kill -0 "$pid" 2>/dev/null && [[ $(stage) != done* && $(stage) != failed* && $(stage) != stopped* ]]
}

echo "run: $OUT"
if ! running; then
  echo "not running; stage: $(stage)"
  [ -f "$OUT/report.md" ] && cat "$OUT/report.md"
  exit 0
fi
ollama ps 2>/dev/null | sed 1d || true

touch "$OUT/run.log"
tail -n +1 -F "$OUT/run.log" 2>/dev/null &
tailpid=$!
trap 'kill $tailpid 2>/dev/null || true' EXIT

last=''
while running; do
  now=$(stage)
  if [ "$now" != "$last" ]; then
    printf '\n== stage: %s (%s)\n' "$now" "$(date +%T)"
    last=$now
  fi
  sleep 2
done
sleep 1
printf '\n== %s (%s)\n' "$(stage)" "$(date +%T)"
[ -f "$OUT/report.md" ] && cat "$OUT/report.md"
exit 0
}
