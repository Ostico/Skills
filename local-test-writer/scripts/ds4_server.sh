#!/usr/bin/env bash
# Start, stop or check the ds4 server the runner talks to with --backend openai.
#
# Usage: ds4_server.sh up [--dir DS4_CHECKOUT] [--stop-ollama] [--wait SECONDS]
#        ds4_server.sh down [--only-started]
#        ds4_server.sh status
#        ds4_server.sh log
#
# up: refuses when an Ollama model of 2 GB or more is loaded (both do not fit) unless --stop-ollama,
# which stops each loaded model first; refuses when another process holds the port. Starts
# Qwen3.8-Flash-Next-Q2 with --ssd-streaming, --ctx 131072, --prefill-chunk 1024 from the ds4
# checkout (--dir, else $DS4_DIR, else the current folder), logs to
# $STATE/ds4-server.log, waits until /v1/models answers (default 180 s), and prints the log's
# memory plan line. A server already answering on the port is left as it is. The pid of a server
# it starts goes in $STATE/ds4-server.pid.
# down: stops the ds4-server whose pid `up` recorded, else every ds4-server, and waits until it
# is gone (it holds about 48 GiB until then). --only-started: the recorded one only, never one
# found by name (the runner's EXIT trap: a server it did not start may serve another run).
# status: whether it runs, what the port answers, and the log path.
# log: the log of the running server, whichever skill started it: of the state folders of
# both skills, the one whose recorded pid is a live ds4-server, else the newest log.
# Environment: DS4_PORT (default 8000), DS4_CTX (default 131072, the runner's --num-ctx must
# match), LTW_STATE_DIR (default ~/.local/state/<skill>, <skill> being the folder this skill is in).
set -uo pipefail

PORT=${DS4_PORT:-8000} CTX=${DS4_CTX:-131072}
# The state folder is named after the skill folder this file sits in (local-test-writer or
# local-code-writer; the real folder, when the skill is installed as a link), so one file
# serves both skills.
SKILL=$(basename "$(cd "$(dirname "$0")/.." && pwd -P)")
STATE=${LTW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$SKILL}
LOG=$STATE/ds4-server.log PIDF=$STATE/ds4-server.pid
URL=http://127.0.0.1:$PORT/v1/models

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 2; }
answers() { curl -sf -m 5 "$URL" > /dev/null; }
holder() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2> /dev/null | awk 'NR > 1 { print $1 " (pid " $2 ")" }' | sort -u; }

cmd=${1:-}; [ -n "$cmd" ] || usage; shift
DIR=${DS4_DIR:-$PWD} STOP_OLLAMA=no WAIT=180 ONLY_STARTED=no
while [ $# -gt 0 ]; do
  case $1 in
    --dir) DIR=$2; shift 2 ;;
    --stop-ollama) STOP_OLLAMA=yes; shift ;;
    --wait) WAIT=$2; shift 2 ;;
    --only-started) ONLY_STARTED=yes; shift ;;
    *) usage ;;
  esac
done

case $cmd in
  up)
    if answers; then
      echo "ds4 already answering at $URL; left as it is (log: $LOG)"
      exit 0
    fi
    if command -v ollama > /dev/null; then
      # Only models of 2 GB or more count: a small embedding model fits beside ds4.
      loaded=$(ollama ps 2> /dev/null | awk 'NR > 1 && (($4 == "GB" && $3 + 0 >= 2) || $4 == "TB") { print $1 }')
      if [ -n "$loaded" ]; then
        if [ "$STOP_OLLAMA" = yes ]; then
          for m in $loaded; do ollama stop "$m" && echo "stopped Ollama model $m"; done
        else
          echo "Ollama has loaded: $(echo $loaded); stop it first (ollama stop <model>) or pass --stop-ollama" >&2
          exit 1
        fi
      fi
    fi
    busy=$(holder)
    [ -z "$busy" ] || { echo "port $PORT is held by $busy and does not answer as ds4" >&2; exit 1; }
    [ -x "$DIR/ds4-server" ] && [ -f "$DIR/gguf/Qwen3.8-Flash-Next-Q2.gguf" ] ||
      { echo "no ds4-server or gguf/Qwen3.8-Flash-Next-Q2.gguf in $DIR: pass --dir or set DS4_DIR" >&2; exit 1; }
    mkdir -p "$STATE"
    # exec, and every stream redirected: no shell is left holding the caller's stdout (a caller
    # in a pipe would wait for the server to stop).
    (cd "$DIR" && exec nohup ./ds4-server -m gguf/Qwen3.8-Flash-Next-Q2.gguf --ssd-streaming \
      --ctx "$CTX" --prefill-chunk 1024 --port "$PORT") > "$LOG" 2>&1 < /dev/null &
    # The subshell execs nohup and nohup execs ds4-server, so $! is the server's pid from the
    # start; by name, pgrep misses it while it is still called bash or nohup.
    pid=$!
    echo "$pid" > "$PIDF"
    echo "starting ds4-server (ctx $CTX, port $PORT), log: $LOG"
    for _ in $(seq "$WAIT"); do
      if answers; then
        grep -m1 'planned' "$LOG" || true
        echo "ready: $URL"
        exit 0
      fi
      kill -0 "$pid" 2> /dev/null || { rm -f "$PIDF"; echo "ds4-server exited; last lines of $LOG:" >&2; tail -n 20 "$LOG" >&2; exit 1; }
      sleep 1
    done
    echo "no answer from $URL after ${WAIT}s; the server is still starting or stuck (log: $LOG)" >&2
    exit 1 ;;
  down)
    pid=$(cat "$PIDF" 2> /dev/null)
    # The recorded pid, while it is still a ds4-server (a pid number can be reused).
    if [ -n "$pid" ] && ps -p "$pid" -o comm= 2> /dev/null | grep -q 'ds4-server$'; then
      kill "$pid"
      for _ in $(seq 60); do
        kill -0 "$pid" 2> /dev/null || { rm -f "$PIDF"; echo "ds4-server stopped (pid $pid)"; exit 0; }
        sleep 1
      done
      echo "ds4-server still running after 60 s: kill -KILL $pid" >&2
      exit 1
    fi
    rm -f "$PIDF"
    [ "$ONLY_STARTED" = no ] || { echo "no ds4-server started by ds4_server.sh up in $STATE: none stopped"; exit 0; }
    pgrep -x ds4-server > /dev/null || { echo "ds4-server not running"; exit 0; }
    pkill -x ds4-server
    for _ in $(seq 60); do
      pgrep -x ds4-server > /dev/null || { echo "ds4-server stopped"; exit 0; }
      sleep 1
    done
    echo "ds4-server still running after 60 s: pkill -KILL -x ds4-server" >&2
    exit 1 ;;
  log)
    if [ -n "${LTW_STATE_DIR:-}" ]; then dirs=("$STATE")
    else base=${XDG_STATE_HOME:-$HOME/.local/state}; dirs=("$base/local-test-writer" "$base/local-code-writer"); fi
    newest=''
    for d in "${dirs[@]}"; do
      [ -f "$d/ds4-server.log" ] || continue
      p=$(cat "$d/ds4-server.pid" 2> /dev/null)
      if [ -n "$p" ] && ps -p "$p" -o comm= 2> /dev/null | grep -q 'ds4-server$'; then
        echo "$d/ds4-server.log"; exit 0
      fi
      if [ -z "$newest" ] || [ "$d/ds4-server.log" -nt "$newest" ]; then newest=$d/ds4-server.log; fi
    done
    echo "${newest:-$LOG}" ;;
  status)
    if pgrep -lx ds4-server; then :; else echo "ds4-server not running"; fi
    if answers; then echo "answers: $URL"; else echo "no answer at $URL"; fi
    echo "log: $LOG" ;;
  *) usage ;;
esac
