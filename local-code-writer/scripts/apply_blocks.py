#!/usr/bin/env python3
"""Apply the SEARCH/REPLACE blocks of a model's reply from aider's run.log, when aider applied
none of them (a second turn dropped them, or any other cause).

Usage: apply_blocks.py RUN_LOG FILE [FILE ...]
       apply_blocks.py --retry-empty RUN_LOG
       apply_blocks.py --count RUN_LOG
       apply_blocks.py --loop RUN_LOG

Run from the repo root. FILE are the only paths a block may change (the runner's --write
files); a block for any other path is skipped and reported. The reply used is the last turn of
run.log (turns end at aider's "Tokens:" lines) that holds a complete block; with thinking on,
only its answer (after the last "**ANSWER**"). A block applies when its SEARCH text is found
exactly in the file (the first match is replaced); an empty SEARCH writes a missing or empty
file, or appends to one with content (aider's rule). A block already applied (by aider, or by a
run of this script) is left as it is: its SEARCH text is gone and its REPLACE text is in the
file, or it inserts lines (REPLACE holds SEARCH) and its REPLACE text is in the file. So the
script can run after aider applied some blocks of the reply and not others. A block cut before its
">>>>>>> REPLACE" is skipped. Prints one line per block and a total; exits 0 when every block
applied or was there, 1 when one did not, 2 on bad arguments.

aider's report of blocks that failed to match repeats them, wrapped at the terminal width: it
is never read as the model's reply.

--retry-empty prints "yes" when aider reported blocks that failed to match and the model's
reply to that report (its retry turn) holds no complete block, else "no": the failed edits are
then only in the reply before.

--count prints "<SEARCH lines> <REPLACE lines>" of the replies after the last "**ANSWER**"
(the whole log without one), aider's failure reports cut out: two different numbers mean a
block without its end.

--loop prints "loop <C> <K> <L>" when the last turn of run.log (the one still streaming) holds
one block of 50 lines or more three times or more in a row, each copy right after the one
before: a model caught in a loop (a thinking model decoded greedily repeats a passage byte for
byte, again and again). C is the length of the repeated block in lines, K how many times it is
there in a row, L its first line in run.log. Else "no". Copies with other text between them do
not count: a thinking reply drafts the code, reviews it, drafts it again and then writes it in
its answer, so three copies of the same code far apart are its normal shape. Blocks of mostly
blank lines are not counted, nor the copies in aider's failure reports.
"""
import os
import re
import sys

SEARCH, DIVIDER, REPLACE = "<<<<<<< SEARCH", "=======", ">>>>>>> REPLACE"
# aider's report of blocks that did not match: its first line, and the lines that can end it
# (the last one present ends it; the model's retry follows).
FAILED = re.compile(r"^# \d+ SEARCH/REPLACE blocks? failed to match!")
FAILED_END = ("Just reply with fixed versions", "Don't re-send them.",
              "The SEARCH section must exactly match")


def chunks(text):
    """@returns run.log split at aider's "Tokens:" lines: each chunk but the last ends a turn."""
    out, cur = [], []
    for line in text.splitlines():
        if line.startswith("Tokens: "):
            out.append(cur)
            cur = []
        else:
            cur.append(line)
    out.append(cur)
    return out


def drop_report(lines):
    """@returns (LINES without aider's report of failed blocks, True when it had one)."""
    start = next((n for n, line in enumerate(lines) if FAILED.match(line)), None)
    if start is None:
        return lines, False
    ends = [n for n, line in enumerate(lines) if n > start and line.startswith(FAILED_END)]
    return lines[:start] + (lines[ends[-1] + 1:] if ends else []), True


def turns(text):
    """@returns The reply texts of run.log, one per chunk, aider's failure reports cut out."""
    return [drop_report(lines)[0] for lines in chunks(text)]


def retry_empty(text):
    """@returns True when the reply to aider's last failure report holds no complete block."""
    parts = chunks(text)
    for n in range(len(parts) - 1, -1, -1):
        lines, reported = drop_report(parts[n])
        if reported:
            # The report after the last turn: the last retry failed, nothing answered it.
            return n < len(parts) - 1 and all(r is None for _, _, r in blocks(lines))
    return False


def count_markers(text):
    """@returns (SEARCH lines, REPLACE lines) of the answer, aider's failure reports cut out."""
    lines = text.splitlines()
    marks = [n for n, line in enumerate(lines) if "**ANSWER**" in line]
    if marks:
        lines = lines[marks[-1]:]
    kept = [line for part in turns("\n".join(lines)) for line in part]
    return (sum(line.startswith(SEARCH) for line in kept),
            sum(line.startswith(REPLACE) for line in kept))


LOOP_LINES, LOOP_TIMES = 50, 3


def find_loop(text):
    """@returns (block lines, times, first line in run.log) of a loop in the last turn, or None."""
    lines = text.splitlines()
    ends = [n for n, line in enumerate(lines) if line.startswith("Tokens: ")]
    first = ends[-1] + 1 if ends else 0
    turn = lines[first:]
    # aider's failure report repeats the blocks it quotes: blank it out, keeping line numbers.
    start = next((n for n, line in enumerate(turn) if FAILED.match(line)), None)
    if start is not None:
        stop = [n for n, line in enumerate(turn) if n > start and line.startswith(FAILED_END)]
        end = stop[-1] + 1 if stop else len(turn)
        turn = turn[:start] + [""] * (end - start) + turn[end:]
    ids, seen = [], {}
    for line in turn:
        ids.append(seen.setdefault(line.rstrip(), len(seen)))
    blank = seen.get("")
    where = {}
    for i in range(len(ids) - LOOP_LINES + 1):
        window = tuple(ids[i:i + LOOP_LINES])
        if sum(t != blank for t in window) * 2 < LOOP_LINES:
            continue
        where.setdefault(window, []).append(i)
    for pos in where.values():
        if len(pos) < LOOP_TIMES:
            continue
        # Two copies of the window at P and Q make a candidate block ids[P:Q]; it is a loop when
        # the next copies of that block follow it with nothing between them.
        for n, p in enumerate(pos):
            for q in pos[n + 1:]:
                size = q - p
                if size < LOOP_LINES:
                    continue
                times = 1
                while ids[p + times * size:p + (times + 1) * size] == ids[p:q]:
                    times += 1
                if times >= LOOP_TIMES:
                    return size, times, first + p + 1
    return None


def blocks(lines):
    """@returns [(path, search, replace or None)] in order; None marks a block cut short."""
    found, i = [], 0
    while i < len(lines):
        if lines[i].rstrip() != SEARCH:
            i += 1
            continue
        # The path is the last line above the block that is neither a fence nor blank.
        j, path = i - 1, None
        while j >= 0:
            above = lines[j].strip()
            if above and not above.startswith("```"):
                path = above.strip("`*")
                break
            j -= 1
        search, replace, k, part = [], [], i + 1, "search"
        while k < len(lines):
            line = lines[k].rstrip()
            if part == "search" and line == DIVIDER:
                part = "replace"
            elif line == REPLACE:
                break
            elif line == SEARCH:  # a new block before this one closed
                k = len(lines)
                break
            elif part == "search":
                search.append(lines[k])
            else:
                replace.append(lines[k])
            k += 1
        done = k < len(lines) and part == "replace"
        found.append((path, "\n".join(search), "\n".join(replace) if done else None))
        i = k + 1 if done else i + 1
    return found


def reply_blocks(text):
    """@returns The blocks of the last turn with a complete block (its answer only)."""
    for lines in reversed(turns(text)):
        marks = [n for n, line in enumerate(lines) if "**ANSWER**" in line]
        if marks:
            lines = lines[marks[-1] + 1:]
        found = blocks(lines)
        if any(rep is not None for _, _, rep in found):
            return found
    return []


def apply(path, search, replace):
    """@returns None when applied, else the reason it was not."""
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    there = bool(replace.strip()) and replace in text
    new = replace + "\n" if replace else ""
    if not search.strip():
        if there:
            return "already in the file"
        text = new if not text.strip() else text + ("" if text.endswith("\n") else "\n") + new
    else:
        # SEARCH still found: apply it, unless the block inserts lines (REPLACE holds SEARCH) and
        # they are there already. A block that removes lines has its REPLACE text in the file
        # before it is applied, so that alone does not mean applied.
        if search not in text:
            return "already in the file" if there else "SEARCH text not found"
        if there and search in replace:
            return "already in the file"
        old = search + "\n"
        if old not in text:
            old, new = search, replace
        text = text.replace(old, new, 1)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return None


def main(argv):
    if argv[:1] == ["--retry-empty"] and len(argv) == 2 and os.path.exists(argv[1]):
        print("yes" if retry_empty(open(argv[1], encoding="utf-8").read()) else "no")
        return 0
    if argv[:1] == ["--count"] and len(argv) == 2 and os.path.exists(argv[1]):
        print("%d %d" % count_markers(open(argv[1], encoding="utf-8", errors="replace").read()))
        return 0
    if argv[:1] == ["--loop"] and len(argv) == 2 and os.path.exists(argv[1]):
        found = find_loop(open(argv[1], encoding="utf-8", errors="replace").read())
        print("loop %d %d %d" % found if found else "no")
        return 0
    if len(argv) < 2 or not os.path.exists(argv[0]):
        sys.stderr.write(__doc__ or "")
        return 2
    allowed = set(argv[1:])
    found = reply_blocks(open(argv[0], encoding="utf-8").read())
    applied = there = 0
    for n, (path, search, replace) in enumerate(found, 1):
        if replace is None:
            print(f"block {n} ({path}): skipped, cut before {REPLACE}")
        elif path not in allowed:
            print(f"block {n} ({path}): skipped, not a --write file")
        else:
            why = apply(path, search, replace)
            print(f"block {n} ({path}): " + (why or "applied"))
            applied += why is None
            there += why == "already in the file"
    print(f"applied {applied} of {len(found)} block(s)"
          + (f", {there} already in the file" if there else ""))
    return 0 if found and applied + there == len(found) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
