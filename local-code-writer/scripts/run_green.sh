#!/usr/bin/env bash
# Run aider with a local reasoning model on an OpenAI-compatible local server (ds4) to write the
# production code that turns failing tests green, inside a guard that undoes anything it touched
# outside the files it was given. The tests stay read-only.
#
# Usage:
#   run_green.sh --brief FILE --model NAME --num-ctx N --write PATH [--write PATH ...]
#                --test-cmd CMD [--read PATH ...] [--repo DIR] [--edit-format diff|whole]
#                [--language English] [--map-tokens 0] [--timeout 0] [--fix-cmd CMD]
#                [--test-dir DIR] [--out DIR] [--lang js|php] [--ds4-dir DIR] [--keep-server]
#
# ds4 and aider only. NAME is the model id or alias the server at OPENAI_API_BASE serves (e.g. a
# -reasoner alias on ds4), as openai/NAME; the window is the server's own (--num-ctx must equal
# it; checked when the server reports context_length), thinking is chosen by the alias.
# --ds4-dir DIR (OPENAI_API_BASE defaults to http://127.0.0.1:8000/v1): when the server does not
# answer, start it from that ds4 checkout with scripts/ds4_server.sh, with --ctx equal to
# --num-ctx, and stop it when the run ends (--keep-server keeps it). A server already answering
# is used and left running.
# PATHs are relative to the repo root (./ and an absolute path inside the repo are accepted and
# made relative; a path outside the repo stops the run, exit 2). A --write PATH named like a test
# file, or a test helper, mock, fixture or test config (testnames.py kind says which), stops the
# run (exit 2): the tests are the check, and the model never edits them or what they lean on. A run that changes no --write
# file is a finding.
# --test-cmd is required: it runs the tests after the model; while it fails, the report says
# "tests still failing". --test-dir is the folder --test-cmd and --fix-cmd run in (their cwd,
# relative to the repo root; default the root), not the folder of the tests. A command whose
# first word does not resolve there stops the run before it starts (exit 2).
# --fix-cmd runs in --test-dir after the model and before the guard (e.g. prettier and eslint
# --fix on the --write files): an edit it makes outside --write is undone too; every error line
# it leaves is a finding.
# The brief's list of the files the model may edit (the template's "You may edit ONLY these
# files:" line, or a line starting "Files:") must be the --write files: a brief written for
# another run of a split task stops the run before it starts (exit 2).
# Writes into OUT (default: a new folder under ~/.local/state/local-code-writer/runs/): a copy of
# the brief, aider's chat and LLM history, run.log, the guard's findings, code.diff (the model's
# lines), the test output, model/ (the model's version of each --write file) and report.md. A run
# always goes to the end: nothing it finds stops it. Every problem (tests still failing, edits
# undone by the guard, placeholders, reasoning or coverage-ignore comments, a file that does not
# parse, aider failing) is a line under "Findings" in report.md, and the script exits 0 once the
# report is written; Claude reviews them. Expected facts (a --write file dirty before the run, a
# SEARCH block the model fixed on aider's retry) go under "Notes". One failure is fatal and fails
# fast: an edit outside --write (by the model or by --fix-cmd), a test file included. A watcher
# stops aider within seconds, the repo goes back as it was before the run, report.md says
# FAILED, and the script exits 3. It exits 2 when no run can start (bad arguments, the model not
# served). Any other exit code is a bug of this script: report.md says RUNNER ERROR, with the
# line that failed. --timeout: seconds before aider is stopped; 0 (the default) never stops it.
# --lang picks the language profile in lang/ (default: the profile whose LANG_EXT lists the first
# --write file's extension). --language defaults to English. With --message-file aider sends one
# message and exits after the reply, so the brief must ask for the edits in that reply. It prints
# OUT when it starts; follow_run.sh follows the latest run live (stage, streamed reply, report).
set -euo pipefail

# The whole body is one { ...; } group: bash reads it to the closing brace before running any of
# it, so editing this file while a run is going cannot break that run (bash otherwise reads a
# script as it runs it). The group ends with exit, so nothing after it is ever read.
{
usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 2; }
refuse() { echo "$1: not in local-code-writer ($2)" >&2; exit 2; }

BRIEF='' MODEL='' NUM_CTX='' REPO='' LANGUAGE=English EDIT_FORMAT=diff MAP_TOKENS=0 TIMEOUT=0
TEST_CMD='' TEST_DIR='' OUT='' FIX_CMD='' TEST_LANG='' DS4_DIR='' KEEP_SERVER=no SERVER_STARTED=no
FINDINGS=()  # problems the review fixes
NOTES=()     # expected facts of the run, reported apart: no effect on the status
SCRIPT_DIR=$(cd "$(dirname -- "$0")" && pwd -P)
WRITE=() READ=()
while [ $# -gt 0 ]; do
  # An option given last with no value: say so, instead of bash's "unbound variable".
  case $1 in
    --keep-server | --help) ;;
    --*) [ $# -ge 2 ] || { echo "$1 needs a value" >&2; exit 2; } ;;
  esac
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
    --fix-cmd) FIX_CMD=$2; shift 2 ;;
    --lang) [ "$2" != none ] || refuse '--lang none' 'its checks need a language profile; leave --lang out to pick it from the file extension'
      TEST_LANG=$2; shift 2 ;;
    --ds4-dir) DS4_DIR=$2; shift 2 ;;
    --keep-server) KEEP_SERVER=yes; shift ;;
    --backend) [ "$2" = openai ] || refuse "--backend $2" 'ds4 only, through OPENAI_API_BASE'; shift 2 ;;
    --agent | --max-turns) refuse "$1" 'aider only' ;;
    --think) refuse "$1" 'thinking is chosen by the model alias' ;;
    --red-lint-ok) refuse "$1" 'GREEN expects no lint error' ;;
    *) usage ;;
  esac
done
[ -n "$BRIEF" ] && [ -n "$MODEL" ] && [ -n "$NUM_CTX" ] && [ ${#WRITE[@]} -gt 0 ] || usage
[ -n "$TEST_CMD" ] || { echo "--test-cmd is required: the tests are the check" >&2; exit 2; }
# Numbers: checked here, so a typo exits 2 instead of failing later as a runner error.
is_count() { case $2 in '' | *[!0-9]*) echo "$1: a whole number, not '$2'" >&2; exit 2 ;; esac; }
is_count --num-ctx "$NUM_CTX"; is_count --timeout "$TIMEOUT"; is_count --map-tokens "$MAP_TOKENS"
NUM_CTX=$((10#$NUM_CTX)) TIMEOUT=$((10#$TIMEOUT))
[ "$NUM_CTX" -gt 0 ] || { echo "--num-ctx: above 0" >&2; exit 2; }
PROVIDER=openai
[ -n "$DS4_DIR" ] && export OPENAI_API_BASE=${OPENAI_API_BASE:-http://127.0.0.1:8000/v1}
[ -n "${OPENAI_API_BASE:-}" ] || { echo "OPENAI_API_BASE is not set (e.g. http://127.0.0.1:8000/v1), or pass --ds4-dir" >&2; exit 2; }
export OPENAI_API_KEY=${OPENAI_API_KEY:-local}
[ -f "$BRIEF" ] || { echo "--brief $BRIEF: no such file" >&2; exit 2; }
BRIEF=$(cd "$(dirname -- "$BRIEF")" && pwd)/$(basename "$BRIEF")
REPO=$(git -C "${REPO:-.}" rev-parse --show-toplevel)
# --write and --read paths in one form, relative to the repo root (no ./, no .., an absolute path
# inside the repo made relative): the watcher and the guard compare them as strings with git's
# paths, so ./a and a must be the same path.
norm_paths() {
  python3 - "$REPO" "$@" <<'PY'
import os, sys
repo = os.path.realpath(sys.argv[1])
for p in sys.argv[2:]:
    q = p
    if os.path.isabs(q):
        head, tail = os.path.split(os.path.normpath(q))
        q = os.path.relpath(os.path.join(os.path.realpath(head), tail), repo)
    q = os.path.normpath(q)
    if q in (".", "..") or q.startswith("../") or os.path.isabs(q) or "\n" in q:
        sys.exit(f"{p}: not a file path inside the repo ({repo})")
    print(q)
PY
}
paths=$(norm_paths "${WRITE[@]}") || exit 2
WRITE=(); while IFS= read -r p; do WRITE+=("$p"); done <<< "$paths"
if [ ${#READ[@]} -gt 0 ]; then
  paths=$(norm_paths "${READ[@]}") || exit 2
  READ=(); while IFS= read -r p; do READ+=("$p"); done <<< "$paths"
fi
# The tests are read-only, and so is what they lean on: a changed mock, fixture or test config
# can make a RED test pass with no code behind it (testnames.py kind says which is which).
for f in "${WRITE[@]}"; do
  [ -d "$REPO/$f" ] && { echo "--write $f is a folder: name each file" >&2; exit 2; }
  [ -L "$REPO/$f" ] && { echo "--write $f is a link: the model would write through it" >&2; exit 2; }
done
kinds=$(python3 "$SCRIPT_DIR/testnames.py" kind "${WRITE[@]}") || { echo "testnames.py kind failed (above)" >&2; exit 2; }
while read -r k f; do
  case $k in
    test) echo "--write $f is named like a test file; tests stay read-only" >&2; exit 2 ;;
    support) echo "--write $f is a test helper, fixture or test config; tests stay read-only" >&2; exit 2 ;;
  esac
done <<< "$kinds"
# The brief's own list of editable files against --write: the model edits what the brief names,
# and a file it names outside --write fails the run at the guard, after the whole model run.
brief_list() {
  python3 - "$BRIEF" <<'PY'
import re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    hit = re.search(r"You may edit ONLY these files:\s*(.*)|^\s*[-*]?\s*Files:\s*(.*)", line)
    if not hit:
        continue
    text = hit.group(1) if hit.group(1) is not None else hit.group(2)
    names = re.findall(r"`([^`]+)`", text)
    if not names:
        text = re.split(r"\.(?:\s|$)", text)[0]
        names = [w for w in re.split(r"[,\s]+", text) if w and w.lower() != "and"]
    print("\n".join(names))
    break
PY
}
brief_files=$(brief_list)
if [ -z "$brief_files" ]; then
  echo "note: the brief has no list of the files to edit (\"You may edit ONLY these files:\" or \"Files:\")" >&2
else
  bf=(); while IFS= read -r p; do [ -n "$p" ] && bf+=("$p"); done <<< "$brief_files"
  paths=$(norm_paths "${bf[@]}") || exit 2
  only_brief=$(comm -23 <(sort -u <<< "$paths") <(printf '%s\n' "${WRITE[@]}" | sort -u))
  only_write=$(comm -13 <(sort -u <<< "$paths") <(printf '%s\n' "${WRITE[@]}" | sort -u))
  if [ -n "$only_brief$only_write" ]; then
    echo "the brief's files to edit and --write differ (a brief written for another run?):" >&2
    [ -n "$only_brief" ] && echo "  in the brief, not in --write: $(tr '\n' ' ' <<< "$only_brief")" >&2
    [ -n "$only_write" ] && echo "  in --write, not in the brief: $(tr '\n' ' ' <<< "$only_write")" >&2
    exit 2
  fi
fi
# Run registry, so a run can be found and followed while it works (scripts/follow_run.sh):
# STATE/current points at the latest run, STATE/runs.tsv has one start and one end line per run,
# OUT/stage names the step under way and OUT/pid this script's pid. OUT defaults to
# STATE/runs/<date>-<time>-<brief name>, which survives a reboot (a temp dir does not), and
# holds a copy of the brief, so a past run can be read again in full. STATE is named after this
# skill's folder, as in ds4_server.sh; follow_run.sh reads the state folders of both skills.
STATE=${LTW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$(basename "$(dirname -- "$SCRIPT_DIR")")}
mkdir -p "$STATE"
OUT=${OUT:-$STATE/runs/$(date +%Y%m%d-%H%M%S)-$(basename "$BRIEF" .md)}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd -P)
# An --out folder inside the repo that git does not ignore: the guard would take the run's own
# files for edits outside --write.
case $OUT/ in
  "$REPO"/*) git -C "$REPO" check-ignore -q "$OUT" ||
    { echo "--out $OUT is inside the repo and not ignored by git: put it outside, or in an ignored folder" >&2; exit 2; } ;;
esac
cp "$BRIEF" "$OUT/brief.md" 2>/dev/null || true  # same file when the brief is already OUT/brief.md
cd "$REPO"
echo $$ > "$OUT/pid"
stage() { echo "$1" > "$OUT/stage"; }
stage starting
ln -sfn "$OUT" "$STATE/current"
printf '%s\tstart\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" $$ "$MODEL" "$REPO" "$OUT" >> "$STATE/runs.tsv"
# Any exit but 0, 2 and 3 is a bug in this script (set -e stopped it): report.md says so, with
# the command the EXIT trap sees and its line, so the run does not look finished. (An ERR trap
# would not do: bash 3.2, macOS's, does not run it when pipefail fails a pipeline.) Inside the
# { } group bash 3.2 gives every command the group's last line as $LINENO, so the line is found
# by the command's text in this file.
on_exit() {
  local ec=$1 cmd=$2 line
  line=$(grep -n -F -- "${cmd%%$'\n'*}" "$0" 2> /dev/null | cut -d: -f1 | head -3 | tr '\n' ' ')
  case $ec in
    0) stage "done 0" ;;
    # Exit 2 before any report: a bad argument or setup, found after the run was registered.
    2) if [ -f "$OUT/report.md" ]; then stage "done 2"
       else stage "stopped before the model (exit 2): the reason is in the runner's output"; fi ;;
    3) stage "failed: edit outside --write (exit 3)" ;;
    *)
      stage "runner error (exit $ec)"
      {
        echo "# local-code-writer run: RUNNER ERROR (exit $ec)"
        echo
        echo "The runner stopped on a bug of its own, not on anything the model did:"
        echo "run_green.sh line ${line:-?}: $cmd"
        echo
        echo "Report it with this file and status-before.txt; nothing after that line ran."
      } > "$OUT/report.md"
      echo "runner error (exit $ec): $OUT/report.md" >&2 ;;
  esac
  printf "%s\tend\t%s\texit %s\t\t%s\n" "$(date "+%F %T")" $$ "$ec" "$OUT" >> "$STATE/runs.tsv"
  if [ "$SERVER_STARTED" = yes ] && [ "$KEEP_SERVER" = no ]; then
    LTW_STATE_DIR=$STATE bash "$SCRIPT_DIR/ds4_server.sh" down --only-started >&2
  fi
}
trap 'on_exit $? "$BASH_COMMAND"' EXIT
FOLLOW=$(command -v lmw-log || echo "bash $SCRIPT_DIR/follow_run.sh   (short name: bash $SCRIPT_DIR/install_lmw_log.sh)")
echo "out:    $OUT" >&2
echo "log:    $OUT/run.log   (the reply as it streams; latest run: $STATE/current/run.log)" >&2
echo "follow: $FOLLOW" >&2

# Language profile: PARSE_RE and FIX_ERROR_RE for this language (lang/<name>.sh);
# without --lang, the profile whose LANG_EXT lists the first --write file's extension.
[ -n "$TEST_LANG" ] || TEST_LANG=$(python3 "$SCRIPT_DIR/testnames.py" profile "${WRITE[0]}")
LANG_LABEL="none (no profile for .${WRITE[0]##*.})" PARSE_RE='' FIX_ERROR_RE=''
if [ "$TEST_LANG" != none ]; then
  if [ -f "$SCRIPT_DIR/lang/$TEST_LANG.sh" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/lang/$TEST_LANG.sh"
  else
    FINDINGS+=("no language profile lang/$TEST_LANG.sh: parse check off")
    TEST_LANG=none
  fi
fi

# --ds4-dir: start the server when it does not answer (it is stopped by the EXIT trap above).
if [ -n "$DS4_DIR" ] && ! curl -sf -m 5 "$OPENAI_API_BASE/models" > /dev/null; then
  stage 'starting ds4'
  port=$(sed -n 's#^[a-z]*://[^:/]*:\([0-9][0-9]*\).*#\1#p' <<< "$OPENAI_API_BASE")
  SERVER_STARTED=yes
  DS4_PORT=${port:-8000} DS4_CTX=$NUM_CTX LTW_STATE_DIR=$STATE \
    bash "$SCRIPT_DIR/ds4_server.sh" up --dir "$DS4_DIR" >&2 || { echo "ds4 did not start (see above)" >&2; exit 2; }
fi

# The server lists its models; an alias is a listed id with a suffix (-reasoner) or an org
# prefix (org/id). Each line: the id, then the window the server reports for it.
ids=$(curl -sf "$OPENAI_API_BASE/models" | python3 -c 'import json,sys; [print("%s\t%s" % (m["id"], m.get("context_length", ""))) for m in json.load(sys.stdin).get("data", [])]') ||
  { echo "no answer from $OPENAI_API_BASE/models: is the server running?" >&2; exit 2; }
known='' server_ctx=''
while IFS=$'\t' read -r id ctx; do
  [ -z "$id" ] && continue
  case $MODEL in "$id" | "$id"-* | */"$id" | */"$id"-*) known=yes; server_ctx=$ctx ;; esac
done <<< "$ids"
[ -n "$known" ] || { echo "model $MODEL not served at $OPENAI_API_BASE (it lists: $(cut -f1 <<< "$ids" | tr '\n' ' '))" >&2; exit 2; }
if [ -n "$server_ctx" ] && [ "$server_ctx" != "$NUM_CTX" ]; then
  echo "--num-ctx $NUM_CTX, but the server's window is $server_ctx: pass --num-ctx $server_ctx" >&2
  exit 2
fi
# The live server's log (its speed lines), whichever skill started the server.
[ -n "$DS4_DIR" ] || pgrep -x ds4-server > /dev/null && echo "ds4 log: $(bash "$SCRIPT_DIR/ds4_server.sh" log)" >&2

# --test-cmd and --fix-cmd run in --test-dir: their first word must resolve there (a path from
# that folder, or a command on PATH), or the run would end with exit 127 after the model.
RUN_DIR=${TEST_DIR:-.}
[ -d "$RUN_DIR" ] || { echo "--test-dir $TEST_DIR: no such folder under the repo root" >&2; exit 2; }
for c in "$TEST_CMD" "$FIX_CMD"; do
  [ -n "$c" ] || continue
  read -r first _ <<< "$c"
  case $first in
    *=*) continue ;;  # VAR=value cmd: not checked
    /*) [ -x "$first" ] || { echo "'$first' is not an executable" >&2; exit 2; } ;;
    */*) if [ ! -x "$RUN_DIR/$first" ]; then
           echo "'$first' is not an executable under --test-dir ${TEST_DIR:-(repo root)}: --test-dir is where the command runs (its cwd), not the tests' folder" >&2
           exit 2
         fi ;;
    *) command -v "$first" > /dev/null || { echo "'$first' (first word of a command) is not on PATH" >&2; exit 2; } ;;
  esac
done

# snap DIR: a copy of each --write file under OUT/DIR.
snap() { local f; for f in "${WRITE[@]}"; do
  if [ -f "$f" ]; then mkdir -p "$OUT/$1/$(dirname -- "$f")"; cp -- "$f" "$OUT/$1/$f"; fi; done; }
# Each --write file as it was before the run: code.diff is measured from it, so a file with
# uncommitted changes still gives only the model's lines.
for f in "${WRITE[@]}"; do
  [ -n "$(git --literal-pathspecs status --porcelain -- "$f")" ] &&
    NOTES+=("$f had uncommitted changes before the run (code.diff is measured from before/)")
done
snap before
# git_status: one "XY path" line per changed path. -z leaves names as they are (git quotes a
# name with a space, a quote or a non-ASCII character otherwise); the second path of a rename or
# copy is dropped.
git_status() { git status --porcelain=v1 -z -uall | perl -0ne 'chomp; if ($s) { $s = 0; next } print "$_\n"; $s = 1 if /^[RC]/'; }
git_status | sort > "$OUT/status-before.txt"
# Files already dirty keep the same status line when edited again, so hash their content too: a
# line of dirty-before.sha missing later is a dirty file changed or deleted since.
hash_dirty() { cut -c4- "$OUT/status-before.txt" | while IFS= read -r p; do
  if [ -f "$p" ]; then printf '%s\0' "$p"; fi; done | xargs -0 shasum -a 256 -- 2> /dev/null | sort || true; }
hash_dirty > "$OUT/dirty-before.sha"
# A copy of each file outside --write that is already dirty, so the guard can put the user's
# uncommitted lines back if the model edits it (git checkout would drop them). A path that is
# dirty because it was deleted has no copy: the guard removes it again.
cut -c4- "$OUT/status-before.txt" | while IFS= read -r p; do
  is_write=no
  for f in "${WRITE[@]}"; do [ "$p" = "$f" ] && is_write=yes; done
  if [ $is_write = no ] && [ -f "$p" ]; then
    mkdir -p "$OUT/dirty-before/$(dirname -- "$p")"; cp -p -- "$p" "$OUT/dirty-before/$p"
  fi
done

# Model settings: no cost; the server has its window and thinking fixed at its side.
{
  echo "- name: $PROVIDER/$MODEL"
  echo "  edit_format: $EDIT_FORMAT"
  echo "  use_repo_map: $([ "$MAP_TOKENS" = 0 ] && echo false || echo true)"
  # Qwen's sampling for thinking mode. Without it aider sends temperature 0, and a thinking
  # model decoded greedily repeats one passage of its thinking until the window is full.
  echo "  use_temperature: 0.6"
  echo "  extra_params:"
  echo "    top_p: 0.95"
  echo "    top_k: 20"
  echo "    min_p: 0"
} > "$OUT/model-settings.yml"
cat > "$OUT/model-metadata.json" <<EOF
{"$PROVIDER/$MODEL": {"max_input_tokens": $NUM_CTX, "max_output_tokens": 16384,
  "input_cost_per_token": 0, "output_cost_per_token": 0,
  "litellm_provider": "$PROVIDER", "mode": "chat"}}
EOF
MODEL_LINE="$MODEL on $OPENAI_API_BASE (window $NUM_CTX, the server's; thinking by the alias; sampling: temperature 0.6, top_p 0.95, top_k 20, min_p 0)"

args=(--model "$PROVIDER/$MODEL" --model-settings-file "$OUT/model-settings.yml"
  --model-metadata-file "$OUT/model-metadata.json" --edit-format "$EDIT_FORMAT"
  --map-tokens "$MAP_TOKENS" --chat-language "$LANGUAGE" --message-file "$BRIEF" --yes-always
  --no-auto-commits --no-dirty-commits --no-gitignore --no-auto-lint --no-auto-test
  --no-suggest-shell-commands --no-detect-urls --no-restore-chat-history
  --analytics-disable --no-check-update --no-show-release-notes --no-fancy-input --no-pretty
  --chat-history-file "$OUT/chat.md" --input-history-file "$OUT/input.txt"
  --llm-history-file "$OUT/llm.txt")
for f in "${WRITE[@]}"; do args+=(--file "$f"); done
for f in ${READ[@]+"${READ[@]}"}; do args+=(--read "$f"); done

# Boundaries: a path is allowed when it is a --write file (aider's own cache aside).
is_allowed() {
  local f
  for f in "${WRITE[@]}"; do [ "$1" = "$f" ] && return 0; done
  case $1 in .aider*) return 0 ;; esac
  return 1
}
# Prints every path changed since the run started that is not allowed.
outside_changes() {
  local line path
  git_status > "$OUT/status-now.txt"
  comm -13 "$OUT/status-before.txt" <(sort "$OUT/status-now.txt") | while IFS= read -r line; do
    path=${line:3}; is_allowed "$path" || echo "$path"; done
  hash_dirty > "$OUT/dirty-now.sha"
  comm -23 "$OUT/dirty-before.sha" "$OUT/dirty-now.sha" | while IFS= read -r line; do
    path=${line:66}; is_allowed "$path" || echo "$path"; done
}

# aider runs through scripts/aider_entry.py, with aider's own Python: it declines "Add file to
# the chat?", which with --yes-always would drop the reply's edits for a second turn. When that
# Python cannot load aider (another install), plain aider runs and the auto-apply below covers.
AGENT_CMD=(aider) AIDER_ENTRY='plain aider'
aider_bin=$(command -v aider || true)
if [ -n "$aider_bin" ]; then
  read -r -a aider_py <<< "$(head -1 "$aider_bin" | sed -n 's/^#![[:space:]]*//p')"
  if [ ${#aider_py[@]} -gt 0 ] && "${aider_py[@]}" -c 'import aider.io, aider.main' 2> /dev/null; then
    AGENT_CMD=("${aider_py[@]}" "$SCRIPT_DIR/aider_entry.py") AIDER_ENTRY='aider_entry.py (file mentions declined)'
  fi
fi
AGENT_CMD+=("${args[@]}")

had_cache=$([ -e .aider.tags.cache.v4 ] && echo yes || echo no)
start=$(date +%s)
stage aider
# From here on no finding stops the run: every step runs and the report is always written. The
# one exception is an edit outside --write: the watcher below stops aider at once (fail fast).
set +eu
# Unbuffered, so the reply reaches run.log as it streams and `tail -f` shows it live.
PYTHONUNBUFFERED=1 perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$TIMEOUT" "${AGENT_CMD[@]}" > "$OUT/run.log" 2>&1 &
aider_pid=$!
stop_agent() { kill -TERM "$aider_pid" 2> /dev/null; sleep 3; kill -KILL "$aider_pid" 2> /dev/null; }
boundary='' LOOP='' tick=0
while kill -0 "$aider_pid" 2> /dev/null; do
  sleep 2
  boundary=$(outside_changes | sort -u)
  if [ -n "$boundary" ]; then stop_agent; break; fi
  # Every 10 s: a reply caught in a loop (one block of lines again and again) never ends by
  # itself; it runs until the window is full, and no edit comes out of it.
  tick=$((tick + 1))
  if [ $((tick % 5)) = 0 ] && [ -f "$OUT/run.log" ]; then
    LOOP=$(python3 "$SCRIPT_DIR/apply_blocks.py" --loop "$OUT/run.log" 2> /dev/null)
    if [ "${LOOP%% *}" = loop ]; then stop_agent; break; fi
    LOOP=''
  fi
done
wait "$aider_pid"
rc=$?
[ -z "$boundary" ] && boundary=$(outside_changes | sort -u)
secs=$(( $(date +%s) - start ))
[ "$had_cache" = no ] && rm -rf .aider.tags.cache.v4
boundary_by=aider

# The reply has edit blocks but no --write file changed: aider dropped them (a second turn after
# adding a file the reply named, or any other cause). Apply them from run.log, to the --write
# files only, before the mechanical fixes.
if [ -z "$boundary" ] && grep -q '^>>>>>>> REPLACE' "$OUT/run.log"; then
  changed=no
  for f in "${WRITE[@]}"; do
    if [ -f "$OUT/before/$f" ]; then cmp -s -- "$OUT/before/$f" "$f" || changed=yes
    elif [ -s "$f" ]; then changed=yes; fi
  done
  if [ $changed = no ]; then
    python3 "$SCRIPT_DIR/apply_blocks.py" "$OUT/run.log" "${WRITE[@]}" > "$OUT/applied-blocks.txt" 2>&1
    why="aider applied none of the reply's edit blocks"
    grep -q 'Add file to the chat?' "$OUT/chat.md" 2> /dev/null &&
      why="$why (it added a file the reply named and sent a second turn)"
    FINDINGS+=("$why; the runner applied what it could from run.log: $(tail -1 "$OUT/applied-blocks.txt") (applied-blocks.txt)")
    boundary=$(outside_changes | sort -u)
  fi
fi
# aider reported SEARCH blocks that did not match and the model's retry turn sent no edit block
# (it said what it would fix and stopped): the failed edits are only in the reply before, often
# written again in full after a block the model broke off. Apply the reply's blocks from run.log;
# apply_blocks.py leaves the ones aider applied (their new text is already in the file).
RETRY_EMPTY=no
if [ -z "$boundary" ] && [ ! -e "$OUT/applied-blocks.txt" ] &&
  [ "$(python3 "$SCRIPT_DIR/apply_blocks.py" --retry-empty "$OUT/run.log" 2> /dev/null)" = yes ]; then
  RETRY_EMPTY=yes
  python3 "$SCRIPT_DIR/apply_blocks.py" "$OUT/run.log" "${WRITE[@]}" > "$OUT/applied-blocks.txt" 2>&1
  FINDINGS+=("aider asked again for the SEARCH block(s) that did not match and the retry turn sent no edit block; the runner applied the reply's blocks from run.log: $(tail -1 "$OUT/applied-blocks.txt") (applied-blocks.txt)")
  boundary=$(outside_changes | sort -u)
fi

# Mechanical fixes (formatting, autofixable lint) before the guard, so it undoes any stray edit.
fix_rc=''
if [ -n "$FIX_CMD" ] && [ -z "$boundary" ]; then
  stage fix
  (cd "${TEST_DIR:-$REPO}" && perl -e 'alarm shift; exec @ARGV' 300 sh -c "$FIX_CMD") > "$OUT/fix-output.txt" 2>&1
  fix_rc=$?
  boundary=$(outside_changes | sort -u)
  [ -n "$boundary" ] && boundary_by='--fix-cmd'
fi

# Guard: every path that changed and is not in --write is undone (and kept in OUT/violations).
stage guard
git_status > "$OUT/status-after.txt"
violations=0 restored=''
# A file already dirty before the run goes back to its copy in OUT/dirty-before/ (or is removed
# again when it was a deletion); the model's version is kept in OUT/violations/.
restore_dirty() {
  mkdir -p "$OUT/violations/$(dirname -- "$1")"
  [ -e "$1" ] && cp -p -- "$1" "$OUT/violations/$1"
  if [ -f "$OUT/dirty-before/$1" ]; then
    mkdir -p "$(dirname -- "$1")"; cp -p -- "$OUT/dirty-before/$1" "$1"
  else
    rm -f -- "$1"
  fi
  echo "restored (was already dirty before the run): $1" >> "$OUT/guard.txt"
  restored+="$1"$'\n'
}
while IFS= read -r line; do
  path=${line:3}
  is_allowed "$path" && continue
  violations=$((violations + 1))
  mkdir -p "$OUT/violations/$(dirname -- "$path")"
  if cut -c4- "$OUT/status-before.txt" | grep -qxF -- "$path"; then
    restore_dirty "$path"
  elif [ "${line:0:2}" = '??' ] || [ "${line:0:1}" = A ]; then
    # A new file, or one aider added to the index (it runs git add on a file it creates): out of
    # the index, then moved away.
    [ "${line:0:1}" = A ] && git --literal-pathspecs rm -q --cached -f -- "$path"
    mv -- "$path" "$OUT/violations/$path"
    echo "removed new file: $path" >> "$OUT/guard.txt"
  else
    git --literal-pathspecs diff HEAD -- "$path" > "$OUT/violations/$path.diff"
    git --literal-pathspecs checkout HEAD -- "$path"
    echo "reverted: $path" >> "$OUT/guard.txt"
  fi
done < <(comm -13 "$OUT/status-before.txt" <(sort "$OUT/status-after.txt"))

hash_dirty > "$OUT/dirty-after.sha"
while IFS= read -r line; do
  path=${line:66}
  is_allowed "$path" && continue
  grep -qxF -- "$path" <<< "$restored" && continue
  restore_dirty "$path"
  violations=$((violations + 1))
done < <(comm -23 "$OUT/dirty-before.sha" "$OUT/dirty-after.sha")

# The model's version, after the mechanical fixes: the baseline the review compares with.
snap model

# Fail fast: an edit outside --write fails the run. The guard above undid it; the --write files
# go back to how they were (the model's version stays in model/), and nothing else runs.
if [ -n "$boundary" ]; then
  for f in "${WRITE[@]}"; do
    if [ -f "$OUT/before/$f" ]; then cp -- "$OUT/before/$f" "$f"; else rm -f -- "$f"; fi
  done
  stage 'failed: edit outside --write'
  {
    echo "# local-code-writer run: FAILED"
    echo
    echo "$boundary_by edited outside --write; the run was stopped after ${secs}s and the repo put back"
    echo "as it was before the run. Paths (the edits are kept in violations/, the guard's log in"
    echo "guard.txt, the model's version of the --write files in model/):"
    echo
    sed 's/^/- /' <<< "$boundary"
    echo
    echo "- model: $MODEL_LINE; aider exit: $rc"
  } > "$OUT/report.md"
  cat "$OUT/report.md"
  echo "out: $OUT"
  exit 3
fi

# Scans over the added lines of the --write files, new untracked files included.
: > "$OUT/code.diff"
for f in "${WRITE[@]}"; do
  [ -f "$f" ] || continue
  base=/dev/null
  [ -f "$OUT/before/$f" ] && base=$OUT/before/$f
  git diff --no-index -- "$base" "$f" >> "$OUT/code.diff"
done
# Words of a stub only, case-sensitive: production code has `placeholder=` attributes and `todos`.
grep -n -E '^\+.*(\bTODO\b|\bFIXME\b|[Nn]ot implemented)' "$OUT/code.diff" > "$OUT/placeholders.txt" || true
# Without thinking, a model may reason inside the code: comments that talk to themselves.
grep -n -E '^\+\s*(//|#|\*).*\b(Wait,|Actually,|Let me|I need to|Hmm|Re-?doing|I issued|should I)' \
  "$OUT/code.diff" > "$OUT/thinking-comments.txt" || true
# A comment that hides a line from the coverage report: the line no test asks for stays hidden.
grep -n -i -E '^\+.*(istanbul ignore|c8 ignore|v8 ignore|node:coverage (ignore|disable)|@codeCoverageIgnore)' \
  "$OUT/code.diff" > "$OUT/coverage-ignore.txt" || true
# Invisible characters written as they are (format characters, default-ignorable code points,
# line and paragraph separators): a reader cannot see them, so the code should use an escape.
python3 - "$OUT/code.diff" > "$OUT/invisible-chars.txt" <<'PY' || true
import sys, unicodedata
IGNORABLE = [(0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160),
             (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E),
             (0x2060, 0x206F), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF),
             (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A),
             (0xE0000, 0xE0FFF)]
def hidden(c):
    o = ord(c)
    return (unicodedata.category(c) in ("Cf", "Zl", "Zp")
            or any(a <= o <= b for a, b in IGNORABLE))
for n, line in enumerate(open(sys.argv[1], encoding="utf-8", errors="replace"), 1):
    if line.startswith("+") and not line.startswith("+++"):
        found = sorted({f"U+{ord(c):04X}" for c in line if hidden(c)})
        if found:
            print(f"{n}: {' '.join(found)}: {line[1:].strip()[:120]}")
PY

# A --write file that does not parse: the profile's own check (lang_parse_check) on each file,
# then PARSE_RE on the test output.
: > "$OUT/parse-errors.txt"
if declare -F lang_parse_check > /dev/null; then
  for f in "${WRITE[@]}"; do [ -f "$f" ] && lang_parse_check "$f" >> "$OUT/parse-errors.txt"; done
fi
stage tests
(cd "${TEST_DIR:-$REPO}" && perl -e 'alarm shift; exec @ARGV' 600 sh -c "$TEST_CMD") > "$OUT/test-output.txt" 2>&1
test_rc=$?
# The tests run the model's code: a file outside --write that changed while they ran (a test
# rewritten, say) is reported, and left as it is for the review.
after_tests=$(outside_changes | sort -u)
[ -n "$PARSE_RE" ] && { grep -n -E "$PARSE_RE" "$OUT/test-output.txt" >> "$OUT/parse-errors.txt" || true; }

# Findings: reported, never acted on here. nlines FILE: its line count.
nlines() { wc -l < "$1" | tr -d ' '; }
[ "$test_rc" = 142 ] && FINDINGS+=("the test command was still running after 600 s (a test hangs?): stopped")
[ -n "$after_tests" ] && FINDINGS+=("the test command changed files outside --write (left as they are): $(tr '\n' ' ' <<< "$after_tests")")
[ "$test_rc" != 0 ] && FINDINGS+=("tests still failing: test command exit $test_rc (test-output.txt)")
# No code written and the tests pass: the test command does not run the RED tests (a filter
# that matches nothing), or they were never red.
[ -s "$OUT/code.diff" ] || FINDINGS+=("no --write file changed (code.diff is empty): do the RED tests run, and fail without the code?")
[ "$rc" = 142 ] && FINDINGS+=("aider stopped by --timeout after ${TIMEOUT}s")
[ -n "$LOOP" ] && { read -r _ n k l <<< "$LOOP"; FINDINGS+=("thinking loop: a block of $n lines repeated $k times from line $l of run.log; aider stopped after ${secs}s"); }
[ -z "$LOOP" ] && [ "$rc" != 0 ] && [ "$rc" != 142 ] && FINDINGS+=("aider exited $rc (run.log)")
[ -s "$OUT/guard.txt" ] && FINDINGS+=("the guard undid $violations edit(s) outside --write (guard.txt, violations/)")
[ -s "$OUT/parse-errors.txt" ] && FINDINGS+=("a file does not parse (parse-errors.txt)")
[ -s "$OUT/invisible-chars.txt" ] && FINDINGS+=("$(nlines "$OUT/invisible-chars.txt") added line(s) with an invisible character written as it is: write it as an escape (invisible-chars.txt)")
[ -s "$OUT/placeholders.txt" ] && FINDINGS+=("$(nlines "$OUT/placeholders.txt") suspected placeholder line(s) (placeholders.txt)")
[ -s "$OUT/thinking-comments.txt" ] && FINDINGS+=("$(nlines "$OUT/thinking-comments.txt") line(s) of reasoning left in comments (thinking-comments.txt)")
[ -s "$OUT/coverage-ignore.txt" ] && FINDINGS+=("$(nlines "$OUT/coverage-ignore.txt") coverage-ignore comment(s) added: remove them (coverage-ignore.txt)")
# A prompt longer than the window: aider warns and still exits 0; an OpenAI-compatible server
# answers 400 (ds4: context_length_exceeded).
over=$(grep -h -o -E 'estimated chat context of [0-9,]+ tokens exceeds the [0-9,]+ token limit|Prompt has [0-9]+ tokens, but the configured context size is [0-9]+' "$OUT/run.log" | head -2 | tr '\n' ';')
[ -n "$over" ] && FINDINGS+=("the prompt is longer than the window: ${over%;} (run.log)")
# A reply cut by the window or the output limit (finish_reason "length"; ds4 stops at the room
# left in its --ctx): aider applies none of its edits, so the files stay as they were.
grep -q -E 'has hit a token limit!' "$OUT/run.log" &&
  FINDINGS+=("the reply hit the token limit and aider applied none of its edits: $(grep -h -o -E 'Total tokens: ~[0-9,]+ of [0-9,]+' "$OUT/run.log" | head -1) (run.log)")
# aider's turns: one line "Tokens: N sent, M received." each. A SEARCH block that does not
# match makes aider ask again; a failure after the last turn's line means a block never applied.
tokens=$(python3 - "$OUT/run.log" <<'PY' 2> /dev/null
import re, sys
rows = re.findall(r"^Tokens: ([\d.]+)([kM]?) sent, ([\d.]+)([kM]?) received",
                  open(sys.argv[1], encoding="utf-8", errors="replace").read(), re.M)
def num(v, u): return float(v) * {"": 1, "k": 1e3, "M": 1e6}[u]
def fmt(x): return f"{x / 1e3:.1f}k" if x >= 1000 else f"{x:.0f}"
if rows:
    sent = sum(num(a, b) for a, b, _, _ in rows); got = sum(num(c, d) for _, _, c, d in rows)
    each = "; ".join(f"{a}{b}/{c}{d}" for a, b, c, d in rows)
    print(f"{fmt(sent)} sent, {fmt(got)} received in {len(rows)} turn(s) ({each})")
PY
)
nomatch=$(grep -c 'SearchReplaceNoExactMatch' "$OUT/run.log" || true)
if [ "${nomatch:-0}" -gt 0 ]; then
  last_tokens=$(grep -n '^Tokens: ' "$OUT/run.log" | tail -1 | cut -d: -f1)
  last_fail=$(grep -n 'SearchReplaceNoExactMatch' "$OUT/run.log" | tail -1 | cut -d: -f1)
  if [ "${last_fail:-0}" -gt "${last_tokens:-0}" ]; then
    FINDINGS+=("$nomatch SEARCH block(s) did not match the file and the last retry still failed: those edits are missing (run.log, SearchReplaceNoExactMatch)")
  elif [ "$RETRY_EMPTY" = no ]; then
    NOTES+=("$nomatch SEARCH block(s) did not match the file at first; aider asked again and the model fixed them ($(grep -c '^Tokens: ' "$OUT/run.log") turns)")
  fi
fi
# An edit block without its closing marker (diff format): aider writes everything up to the next
# block into one file, fences included, and can leave the next file empty. Only the answer is
# counted (apply_blocks.py --count): with thinking on, run.log shows the reasoning first and the
# answer under "**ANSWER**"; aider's report of blocks that failed to match is cut out.
if [ "$EDIT_FORMAT" = diff ]; then
  read -r n_search n_replace < <(python3 "$SCRIPT_DIR/apply_blocks.py" --count "$OUT/run.log" || echo 0 0)
  [ "$n_search" != "$n_replace" ] &&
    FINDINGS+=("the reply has $n_search SEARCH block(s) but $n_replace '>>>>>>> REPLACE': a block without its end runs on into the next, so aider either wrote that text into a file (a file can hold the next block's text or stay empty) or found no match (run.log)")
fi
if [ -n "$fix_rc" ] && [ "$fix_rc" != 0 ]; then
  if [ -n "$FIX_ERROR_RE" ]; then
    left=$(grep -c -E "$FIX_ERROR_RE" "$OUT/fix-output.txt" || true)
    [ "${left:-0}" != 0 ] && FINDINGS+=("$left error(s) left after --fix-cmd (fix-output.txt)")
  else
    FINDINGS+=("--fix-cmd exited $fix_rc (fix-output.txt)")
  fi
fi

{
  echo "# local-code-writer run"
  echo
  echo "- agent: aider, through $AIDER_ENTRY"
  echo "- model: $MODEL_LINE, edit format $EDIT_FORMAT, repo map tokens $MAP_TOKENS"
  echo "- aider exit: $rc, time: ${secs}s (timeout ${TIMEOUT}s); tokens: ${tokens:-none reported}"
  [ -n "$fix_rc" ] && echo "- fix command exit: $fix_rc (output in fix-output.txt)"
  echo "- language: $LANG_LABEL"
  echo "- test command exit: $test_rc (output in test-output.txt)"
  echo "- guard: $( [ -s "$OUT/guard.txt" ] && cat "$OUT/guard.txt" | tr '\n' ';' || echo 'no edits outside --write')"
  echo "- suspected placeholders: $(nlines "$OUT/placeholders.txt")"
  echo "- reasoning left in comments: $(nlines "$OUT/thinking-comments.txt") (thinking-comments.txt)"
  echo "- coverage-ignore comments: $(nlines "$OUT/coverage-ignore.txt") (coverage-ignore.txt)"
  [ -s "$OUT/parse-errors.txt" ] && echo "- PARSE ERRORS: $(nlines "$OUT/parse-errors.txt") lines (parse-errors.txt)"
  echo
  echo "- the model's version of each --write file: model/<path>; its lines: code.diff"
  echo
  echo "## Findings"
  echo
  if [ ${#FINDINGS[@]} -eq 0 ]; then echo "none"; else printf -- '- %s\n' "${FINDINGS[@]}"; fi
  echo
  echo "## Notes"
  echo
  if [ ${#NOTES[@]} -eq 0 ]; then echo "none"; else printf -- '- %s\n' "${NOTES[@]}"; fi
  echo
  echo "Read code.diff yourself before trusting any of this, then run the type check, the lint and"
  echo "the coverage: green means all of them pass, not only the tests."
} > "$OUT/report.md"
cat "$OUT/report.md"
echo "out: $OUT"

exit 0
}
