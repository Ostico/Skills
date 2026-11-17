#!/usr/bin/env python3
"""How much the review changed the local model's tests, test by test.

Usage: review_stats.py [--lang NAME] [--report OUT/report.md] MODEL_FILE FINAL_FILE [...]
       review_stats.py [--lang NAME] --run OUT [REPO]
       review_stats.py [--lang NAME] --existing BEFORE_FILE MODEL_FILE [BRIEF]
       review_stats.py [--lang NAME] --count-new BEFORE_FILE MODEL_FILE

MODEL_FILE is the model's version (the runner keeps it in OUT/model/<path>, after --fix-cmd, so
formatting and lint autofixes do not count); FINAL_FILE is the test file after the review. The
file as it was before the run is OUT/before/<path> (found from MODEL_FILE's path): a test that
was there before and that neither the model nor the review changed is left out of every count.
For JavaScript and TypeScript tests are matched by name, test(...) and it(...) blocks, with
typographic quotes and runs of spaces in the name read as plain ones, so a name fixed only in
its quotes is one test, fixed. For PHP (PHPUnit) a test is a method named test* or marked
#[Test] or @test, from its `function` line to the closing brace at its own indent; matched by
method name. Tests are compared on their own text, so new tests inserted inside or next to an
existing one do not make it changed. Each test is:
  kept       unchanged (whitespace aside);
  fixed      changed, at least half of its lines as the model wrote them (similarity >= 0.5),
             or an existing test the model changed and the review put back as it was;
  rewritten  changed more than that;
             (a new test whose name changed in review, or that the splitter read short because
             of a quote inside the name, is matched to the final one by its body, when at least
             half of it is the same, and counted as above);
  removed    a new test in the model's version, not in the final one;
  deleted    an existing test the model deleted and the review left deleted: the task asked
             for it (the review puts back every deletion the brief did not ask for);
  added      in the final one only (written in the review).
The splitter is picked by the file's language profile: --lang NAME (the runner passes its own
--lang), else testnames.py profile (the lang/<name>.sh whose LANG_EXT lists the extension).
For a profile without a splitter here, or no profile, the file is compared as a whole: one
row, kept, fixed or rewritten.
Prints a table and the totals: the share of the final test lines that the review changed or
added; then the run's status:
  DONE WITH WARNING  a test rewritten, removed or written in the review (serious errors fixed);
  DONE WITH NOTICE   only small fixes, or runner findings fixed (--report: its Findings);
  DONE               nothing to fix.
With --report, the same output also goes to review.md next to report.md (readable when the
shell compresses command output).
--run OUT [REPO] compares every file under OUT/model/ with the same path under REPO (default:
the current folder, the repo root) and reads OUT/report.md as --report does, so a run with many
--write files needs no pairs. Like --report, it writes OUT/review.md.
A run that failed on an edit outside --write (runner exit 3) is FAIL; this script is not run.
A --report file that does not exist (the runner died before writing it) gives a warning and no
runner findings.
It exits 2, printing this text, on an unknown option, a file that does not exist, or a
MODEL_FILE that is not under OUT/model/.

--existing prints one line per test of BEFORE_FILE that MODEL_FILE changed or removed
("existing test changed: <name>"); for a language without a test splitter, the count of the
lines it changed or removed. With BRIEF, a test its "## Existing tests that change" section
names (in backticks, anywhere in the section, even wrapped over two lines) is printed as
"as briefed: ..." instead, and one it names that the model left as it was
as "briefed change not made: <name>". A mechanical change the section gives by pattern, as
`old` -> `new` on a line (a rename in every test, say), makes a changed test "as briefed" when
its lines before the run, with every such replacement made, are the model's lines. The runner
adds every line but the "as briefed" ones to its Findings.

--count-new prints the number of tests in MODEL_FILE that BEFORE_FILE (missing: none) does not
have, or "n/a" for a language without a test splitter; the runner's test count for PHP.
"""
import difflib
import os
import re
import sys

sys.dont_write_bytecode = True  # no __pycache__ in the skill folder for the import below
from testnames import profile_of  # noqa: E402

LANG = None  # --lang: the profile for every file, instead of the one picked by extension
JS_TEST = re.compile(r"""^(\s*)(?:test|it)(?:\.each\(.*?\))?(?:\.\w+)?\(\s*(['"`])(.+?)\2""")
PHP_METHOD = re.compile(
    r"^(\s*)(?:(?:public|protected|private|static|final|abstract)\s+)*function\s+(\w+)\s*\(")
PHP_TEST_MARK = re.compile(r"#\[(?:\\?PHPUnit\\Framework\\Attributes\\)?Test\b|@test\b")
WHOLE = "(whole file)"
QUOTES = str.maketrans({"‘": "'", "’": "'", "‛": "'", "ʼ": "'",
                        "“": '"', "”": '"', "„": '"'})


def norm(name):
    """The key a test is matched by: plain quotes, single spaces."""
    return " ".join(name.translate(QUOTES).split())


def tests(path):
    """@returns {key: (name, [lines])} for each test block, in file order; the whole file as one
    block for a language without a test splitter; {} for a missing file."""
    if not path or not os.path.exists(path):
        return {}
    lines = open(path, encoding="utf-8").read().splitlines()
    splitter = SPLITTERS.get(LANG or profile_of(path))
    if splitter is None:
        return {WHOLE: (WHOLE, [l.strip() for l in lines if l.strip()])}
    return splitter(lines)


def js_tests(lines):
    """@returns {key: (name, [lines])} for each test(...) or it(...) block."""
    found = {}
    i = 0
    while i < len(lines):
        hit = JS_TEST.match(lines[i])
        if hit is None:
            i += 1
            continue
        indent, name = len(hit.group(1)), hit.group(3)
        # The block ends at the first line back at the test's own indentation that closes the
        # call: `})`, `}, 10000)`, `}, { timeout: 5 })`. A test on one line (its brackets close
        # on it, as test('a', () => { ... })) is that line alone. Strings and comments do not
        # count.
        end = i + 1
        first = code_of(lines[i])
        one_line = (first.count("(") == first.count(")") and first.count("{") == first.count("}")
                    and first.endswith(")"))
        while end < len(lines) and not one_line:
            line = lines[end]
            if len(line) - len(line.lstrip()) == indent and JS_CLOSE.match(code_of(line)):
                end += 1
                break
            end += 1
        block = [l.strip() for l in lines[i:end] if l.strip()]
        key, n = norm(name), 2
        while key in found:  # Same name twice: keep both, numbered.
            key, n = f"{norm(name)} #{n}", n + 1
        found[key] = (name, block)
        i = end
    return found


JS_CLOSE = re.compile(r"^\}.*\)$")


def code_of(line):
    """LINE with its string literals emptied and its // comment cut, stripped of spaces and a
    trailing semicolon: what is left to count brackets on."""
    out, quote, i = [], None, 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                out.append(c)
                quote = None
        elif c in "'\"`":
            out.append(c)
            quote = c
        elif line.startswith("//", i):
            break
        else:
            out.append(c)
        i += 1
    return "".join(out).strip().rstrip(";").rstrip()


def php_marked(lines, i):
    """@returns Whether the attribute or doc comment lines right above line i mark a test."""
    j = i - 1
    while j >= 0:
        line = lines[j].strip()
        if not (line.startswith(("#[", "*", "/**", "*/", "//")) or line.endswith("*/")):
            return False
        if PHP_TEST_MARK.search(line):
            return True
        j -= 1
    return False


def php_tests(lines):
    """@returns {name: (name, [lines])} for each PHPUnit test method: named test*, or marked
    #[Test] / @test above it; the block runs from the function line to the first line at the
    method's own indent that starts with a closing brace."""
    found = {}
    for i, line in enumerate(lines):
        hit = PHP_METHOD.match(line)
        if hit is None:
            continue
        name = hit.group(2)
        if not (name.startswith("test") or php_marked(lines, i)):
            continue
        indent, end = len(hit.group(1)), i
        if not line.rstrip().endswith("}"):  # not a one-line method
            end = i + 1
            while end < len(lines):
                other = lines[end]
                if len(other) - len(other.lstrip()) == indent and other.strip().startswith("}"):
                    break
                end += 1
        block = [l.strip() for l in lines[i:end + 1] if l.strip()]
        key, n = name, 2
        while key in found:
            key, n = f"{name} #{n}", n + 1
        found[key] = (name, block)
    return found


# Test splitters by language profile name (lang/<name>.sh).
SPLITTERS = {"js": js_tests, "php": php_tests}


def before_of(model_file):
    """OUT/model/<path> -> OUT/before/<path>, the file as it was before the run."""
    head, sep, tail = model_file.rpartition("/model/")
    return f"{head}/before/{tail}" if sep else None


def body(entry):
    return entry[1] if entry else None


def pair_renamed(before, model, final):
    """A new test of the model with no final test of its name, and a final test with no model
    test of its name, are one test when their bodies are at least half the same (a name fixed
    in review, or one the splitter cut short: a quote inside a name). @returns model renamed
    to the final names, so compare() matches them."""
    lost = [k for k in model if k not in final and k not in before]
    new = [k for k in final if k not in model and k not in before]
    pairs = []
    for m in lost:
        for f in new:
            ratio = difflib.SequenceMatcher(None, model[m][1], final[f][1], autojunk=False).ratio()
            if ratio >= 0.5:
                pairs.append((ratio, m, f))
    renamed, used = {}, set()
    for _, m, f in sorted(pairs, reverse=True):
        if m not in renamed and f not in used:
            renamed[m] = f
            used.add(f)
    return {renamed.get(k, k): v for k, v in model.items()}


def compare(model_file, final_file):
    """@returns [(name, status, model lines, final lines, share changed, existing)]."""
    before = tests(before_of(model_file))
    model, final = tests(model_file), tests(final_file)
    model = pair_renamed(before, model, final)
    rows = []
    keys = list(model) + [k for k in final if k not in model]
    keys += [k for k in before if k not in model and k not in final]
    for key in keys:
        b0, a, b = body(before.get(key)), body(model.get(key)), body(final.get(key))
        entry = final.get(key) or model.get(key) or before.get(key)
        name = entry[0] if entry else key
        existing = b0 is not None
        if existing and a == b0 and b == b0:
            continue  # There before, untouched by the model and by the review.
        if b is None:
            if existing and a is None:  # Deleted by the model, as the task asked.
                rows.append((name, "deleted", len(b0 or []), 0, 0.0, existing))
            elif existing:  # A deletion the model missed or replaced with a change.
                rows.append((name, "fixed", len(a or []), 0, 0.0, existing))
            else:
                rows.append((name, "removed", len(a or []), 0, 0.0, existing))
            continue
        if existing and b == b0:  # The model changed or removed it; the review put it back.
            rows.append((name, "fixed", len(a or []), len(b), 0.0, existing))
            continue
        if a is None:
            rows.append((name, "added", 0, len(b), 1.0, existing))
            continue
        matcher = difflib.SequenceMatcher(None, a, b, autojunk=False)
        same = sum(m.size for m in matcher.get_matching_blocks())
        changed = len(b) - same  # Final lines the review changed or added.
        ratio = matcher.ratio()
        status = "kept" if a == b else ("fixed" if ratio >= 0.5 else "rewritten")
        rows.append((name, status, len(a), len(b), changed / len(b) if b else 0.0, existing))
    return rows


def briefed(brief):
    """@returns The brief's "## Existing tests that change" section as one line, with runs of
    spaces and line breaks read as one space: a test is named there when "`<its name>`" is in
    it, wherever the line breaks (a name can wrap) and however many tests one bullet names."""
    lines, inside = [], False
    if not brief or not os.path.exists(brief):
        return ""
    for line in open(brief, encoding="utf-8").read().splitlines():
        if line.startswith("## "):
            inside = line[3:].strip().lower().startswith("existing tests that change")
        elif inside:
            lines.append(line)
    return norm(" ".join(lines))


PATTERN = re.compile(r"`([^`]+)`\s*(?:->|\u2192)\s*`([^`]*)`")


def by_pattern(block, section):
    """@returns BLOCK with every `old` -> `new` replacement of the brief's section made."""
    pairs = PATTERN.findall(section)
    out = []
    for line in block:
        for old, new in pairs:
            line = line.replace(old, new)
        out.append(line)
    return out


def existing_changed(before_file, model_file, brief=None):
    """@returns One line per test of before_file that model_file changed or removed, and one
    per test the brief names that the model left as it was."""
    before, model, section = tests(before_file), tests(model_file), briefed(brief)
    patterned = bool(PATTERN.search(section))
    out = []
    for key, (name, block) in before.items():
        asked = {key} if f"`{key}`" in section else set()
        other = body(model.get(key))
        if key == WHOLE:
            ops = difflib.SequenceMatcher(None, block, other or [], autojunk=False).get_opcodes()
            gone = sum(i2 - i1 for tag, i1, i2, _, _ in ops if tag in ("delete", "replace"))
            if gone:
                out.append(f"existing lines changed or removed: {gone}")
            continue
        tag = "as briefed: " if key in asked else ""
        how = ""
        if not tag and other is not None and patterned and by_pattern(block, section) == other:
            tag, how = "as briefed: ", " (by pattern)"
        if other is None:
            out.append(f"{tag}existing test removed: {name}")
        elif other != block:
            out.append(f"{tag}existing test changed: {name}{how}")
        elif key in asked:
            out.append(f"briefed change not made: {name}")
    return out


def runner_findings(report):
    """@returns The lines under "## Findings" in the runner's report.md ("none" gives [])."""
    lines, inside = [], False
    if not os.path.exists(report):
        sys.stderr.write(f"review_stats.py: warning: no {report} (the runner did not finish): "
                         "no runner findings counted\n")
        return lines
    for line in open(report, encoding="utf-8").read().splitlines():
        if line.startswith("## "):
            inside = line.strip() == "## Findings"
        elif inside and line.startswith("- "):
            lines.append(line[2:])
    return lines


def usage(why):
    sys.stderr.write(f"review_stats.py: {why}\n\n{__doc__ or ''}")
    return 2


def main(argv):
    global LANG
    if argv[:1] == ["--lang"]:
        if len(argv) < 2:
            return usage("--lang takes a profile name")
        LANG, argv = argv[1], argv[2:]
    unknown = [a for a in argv if a.startswith("--")
               and a not in ("--existing", "--report", "--count-new", "--run")]
    if unknown:
        return usage(f"unknown option {unknown[0]}")
    if argv[:1] == ["--existing"]:
        if len(argv) not in (3, 4):
            return usage("--existing takes BEFORE_FILE MODEL_FILE [BRIEF]")
        for line in existing_changed(argv[1], argv[2], argv[3] if len(argv) == 4 else None):
            print(line)
        return 0
    if argv[:1] == ["--count-new"]:
        if len(argv) != 3:
            return usage("--count-new takes BEFORE_FILE MODEL_FILE")
        before, model = tests(argv[1]), tests(argv[2])
        print("n/a" if WHOLE in model else sum(1 for k in model if k not in before))
        return 0
    findings, report = [], None
    if argv[:1] == ["--run"]:
        if len(argv) not in (2, 3):
            return usage("--run takes OUT [REPO]")
        out_dir, repo = argv[1], argv[2] if len(argv) == 3 else "."
        model_root = os.path.join(out_dir, "model")
        if not os.path.isdir(model_root):
            return usage(f"no {model_root}: not a runner's OUT folder, or a failed run")
        pairs = []
        for root, _, files in sorted(os.walk(model_root)):
            for name in sorted(files):
                model_file = os.path.join(root, name)
                rel = os.path.relpath(model_file, model_root)
                pairs += [model_file, rel if repo == "." else os.path.join(repo, rel)]
        argv = ["--report", os.path.join(out_dir, "report.md")] + pairs
    if argv[:1] == ["--report"] and len(argv) > 1:
        report = argv[1]
        findings, argv = runner_findings(report), argv[2:]
    if len(argv) < 2 or len(argv) % 2:
        return usage("MODEL_FILE FINAL_FILE pairs expected")
    missing = [a for a in argv if not os.path.exists(a)]
    if missing:
        return usage(f"no such file {missing[0]}")
    not_model = [m for m in argv[::2] if before_of(m) is None]
    if not_model:
        return usage(f"{not_model[0]} is not a model version (OUT/model/<path>)")
    out = []
    totals = {"kept": 0, "fixed": 0, "rewritten": 0, "removed": 0, "deleted": 0, "added": 0}
    final_lines = changed_lines = touched_existing = 0
    for model_file, final_file in zip(argv[::2], argv[1::2]):
        out += [f"## {final_file}", "", "| test | status | model lines | final lines | changed |",
                "|---|---|---|---|---|"]
        for name, status, a, b, share, existing in compare(model_file, final_file):
            totals[status] += 1
            touched_existing += existing
            final_lines += b
            changed_lines += round(share * b)
            label = f"{name} (existing)" if existing else name
            out.append(f"| {label} | {status} | {a} | {b} | {share:.0%} |")
        out.append("")
    written = (totals["kept"] + totals["fixed"] + totals["rewritten"] + totals["removed"]
               + totals["deleted"])
    pct = changed_lines / final_lines if final_lines else 0.0
    out.append(
        f"Model tests: {written}; kept {totals['kept']}, fixed {totals['fixed']}, "
        f"rewritten {totals['rewritten']}, removed {totals['removed']}; added in review "
        f"{totals['added']}; existing tests deleted as the task asked {totals['deleted']}. "
        f"Existing tests among them: {touched_existing} (unchanged ones left out)."
    )
    out.append(f"Changed in review: {pct:.0%} of the final test lines ({changed_lines} of {final_lines}).")
    serious = totals["rewritten"] + totals["removed"] + totals["added"]
    if serious:
        status = "DONE WITH WARNING"
        why = (f"{totals['rewritten']} rewritten, {totals['removed']} removed, "
               f"{totals['added']} written in review")
    elif totals["fixed"] or findings:
        status = "DONE WITH NOTICE"
        why = f"{totals['fixed']} fixed, {len(findings)} runner finding(s) fixed"
    else:
        status, why = "DONE", "nothing to fix"
    out.append(f"Status: {status} ({why})")
    text = "\n".join(out) + "\n"
    sys.stdout.write(text)
    if report:
        with open(os.path.join(os.path.dirname(report) or ".", "review.md"), "w", encoding="utf-8") as f:
            f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
