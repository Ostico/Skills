#!/usr/bin/env python3
"""Run pi in JSON mode for run_aider_tests.sh --agent pi, and keep its output readable.

Usage: pi_run.py OUT -- pi [pi arguments]

Writes, as the run goes: OUT/events.jsonl (pi's events, one per line), OUT/run.log (the reply
text, and one line per tool call and its result, flushed so `tail -f` follows it) and
OUT/pi-stderr.txt (pi's stderr, with pi_guard.ts's "pi-guard: ..." lines). At the end, also
when stopped by a signal, OUT/pi-summary.txt has one key=value line each: turns, tool_calls (by
tool), tool_errors (failed calls, pi_guard.ts's refusals apart), blocked (edits pi_guard.ts
refused), turn_limit (yes or no), stop (the last reply's stop reason), error (its error
message, if any), tokens (as the server reported them). SIGTERM, SIGINT and SIGALRM (the
runner's --timeout) stop pi's whole process group, after a grace of 2 s (shorter than the
runner's 3 s, so pi_run is never killed first). The exit code is pi's, or 128 plus the number
of the signal that stopped pi or pi_run. A crash of pi_run itself stops pi too and exits 1,
with the traceback in the runner's pi-run.txt.
"""
import json
import os
import signal
import subprocess
import sys
import threading
import traceback

GRACE = 2  # seconds between SIGTERM and SIGKILL to pi's process group
# pi_guard.ts's refusal reasons: not counted as failed tool calls.
GUARD_REASONS = ("only these files may be changed", "turn limit ")

if len(sys.argv) < 4 or sys.argv[2] != "--":
    sys.stderr.write(__doc__ or "")
    sys.exit(2)
out, cmd = sys.argv[1], sys.argv[3:]
log = open(os.path.join(out, "run.log"), "w", encoding="utf-8")
events = open(os.path.join(out, "events.jsonl"), "w", encoding="utf-8")
errfile = open(os.path.join(out, "pi-stderr.txt"), "w", encoding="utf-8")
child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         bufsize=1, start_new_session=True)
assert child.stdout is not None and child.stderr is not None

turns = errors = 0
tools, usage, last = {}, {"input": 0, "output": 0}, {}


def fmt(x):
    return f"{x / 1e3:.1f}k" if x >= 1000 else str(x)


def write_summary():
    """OUT/pi-summary.txt from what the events said so far."""
    try:
        stderr_text = open(os.path.join(out, "pi-stderr.txt"), encoding="utf-8").read()
    except OSError:
        stderr_text = ""
    tokens = f"{fmt(usage['output'])} received in {turns} turn(s)"
    tokens += (f", {fmt(usage['input'])} sent" if usage["input"]
               else " (input not reported by the server)")
    summary = {
        "turns": turns,
        "tool_calls": ", ".join(f"{k} {v}" for k, v in sorted(tools.items())) or "none",
        "tool_errors": errors,
        "blocked": stderr_text.count("pi-guard: blocked"),
        "turn_limit": "yes" if "pi-guard: turn limit" in stderr_text else "no",
        "stop": last.get("stopReason", "none"),
        "error": " ".join(str(last.get("errorMessage", "")).split())[:300],
        "tokens": tokens,
    }
    with open(os.path.join(out, "pi-summary.txt"), "w", encoding="utf-8") as f:
        for k, v in summary.items():
            f.write(f"{k}={v}\n")


def kill_pi():
    """Stop pi's whole process group: SIGTERM, then SIGKILL after GRACE seconds."""
    for sig, wait in ((signal.SIGTERM, GRACE), (signal.SIGKILL, 1)):
        try:
            os.killpg(child.pid, sig)
            child.wait(timeout=wait)
            return
        except (ProcessLookupError, PermissionError):
            return
        except subprocess.TimeoutExpired:
            continue


def stop(signum, _frame):  # noqa: ARG001
    """Stop pi, write the summary, then exit as killed by that signal."""
    kill_pi()
    try:
        errfile.flush()
        write_summary()
        log.write(f"\n[pi_run: stopped by signal {signum}]\n")
        log.flush()
    except (OSError, RuntimeError):  # a write the signal interrupted: the summary comes first
        pass
    os._exit(128 + signum)


for s in (signal.SIGTERM, signal.SIGINT, signal.SIGALRM):
    signal.signal(s, stop)


def copy_stderr():
    stream = child.stderr
    assert stream is not None
    for line in stream:
        errfile.write(line)
        errfile.flush()


copier = threading.Thread(target=copy_stderr, daemon=True)
copier.start()


def as_dict(x):
    return x if isinstance(x, dict) else {}


def handle(e):
    """One pi event: run.log lines and the counts."""
    global turns, errors, last
    kind = e.get("type")
    if kind == "message_update":
        ev = as_dict(e.get("assistantMessageEvent"))
        if ev.get("type") == "text_delta":
            log.write(str(ev.get("delta", "")))
    elif kind == "tool_execution_start":
        name = str(e.get("toolName", "?"))
        tools[name] = tools.get(name, 0) + 1
        args = as_dict(e.get("args"))
        log.write(f"\n>> {name} {args.get('path', args.get('pattern', ''))}\n")
    elif kind == "tool_execution_end":
        if e.get("isError"):
            content = as_dict(e.get("result")).get("content")
            text = ""
            if isinstance(content, list) and content:
                text = str(as_dict(content[0]).get("text", ""))
            if not text.startswith(GUARD_REASONS):
                errors += 1
            log.write(f"<< ERROR: {text[:200]}\n")
        else:
            log.write("<< ok\n")
    elif kind == "turn_end":
        turns += 1
    elif kind == "message_end":
        message = as_dict(e.get("message"))
        if message.get("role") == "assistant":
            last = message
            for k in usage:
                n = as_dict(message.get("usage")).get(k, 0)
                usage[k] += int(n) if isinstance(n, (int, float)) else 0


try:
    for line in child.stdout:
        events.write(line)
        events.flush()
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if isinstance(e, dict):
            handle(e)
        log.flush()
except Exception:  # noqa: BLE001  a bug here must not leave pi running
    traceback.print_exc()
    kill_pi()
    write_summary()
    sys.exit(1)
rc = child.wait()
copier.join(timeout=5)
errfile.flush()
write_summary()
sys.exit(128 - rc if rc < 0 else rc)
