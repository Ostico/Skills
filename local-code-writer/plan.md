# local-code-writer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone skill that hands the GREEN step of a planned task (the production code
that turns its RED tests green) to a local reasoning model, in small checked runs, with Claude
planning before and reviewing after.

**Architecture:** `local-code-writer` carries its own runner (`scripts/run_green.sh`, cut down
from `local-test-writer`'s `run_aider_tests.sh`) and unchanged copies of the shared helper
files. A `sync_shared.sh` script, present in both skills, shows where the shared files drift
apart. Each skill gets a `README.md` for people that names the sync script.

**Tech Stack:** bash 3.2 (macOS), Python 3 (stdlib only), aider, ds4.

**Spec:** `local-code-writer/design.md` (read it first; this plan argues from it).

## Global Constraints

- Every file in English; never the em-dash character (U+2014).
- The skills stay generic: no project names in `SKILL.md`, `README.md`, the template or
  `lessons.md`; project names only in `references/findings.local.md`.
- Never run a local model without the owner's go for that run; never stop a run.
- No commit until the owner asks ("committa"); never push to main; no Co-Authored-By trailer.
- Use `/usr/bin/git`; scratch files only under `$CLAUDE_JOB_DIR/tmp`.
- `local-test-writer` keeps its behaviour: its only changes are the state-folder default in
  `ds4_server.sh` and `follow_run.sh` (same result for it), `sync_shared.sh` and `README.md`.
- `local-code-writer` must work with `local-test-writer` absent.
- `SKILL.md`, `README.md` and the template follow the owner's speak-simple style, detailed but
  clear.

## Review Focus

1. A `--write` path named like a test file: `run_green.sh` refuses to start (exit 2), so the
   model can never change a test. Task 2.
2. A run without `--test-cmd`: refused (exit 2); a GREEN run with no tests checks nothing.
   Task 2.
3. A run whose tests still fail: a finding, never "Findings: none". Task 2.
4. `local-test-writer` not installed: `sync_shared.sh` exits 0 with a note, and
   `run_green.sh` runs. Tasks 1 and 2.
5. A shared file edited in one skill only: `sync_shared.sh` names it and exits 1. Task 1.

---

### Task 1: shared files, state folder, `sync_shared.sh`

**Files:**
- Modify: `local-test-writer/scripts/ds4_server.sh:21`, `local-test-writer/scripts/follow_run.sh:16`
  (the state-folder default)
- Create: `local-code-writer/scripts/{apply_blocks.py,aider_entry.py,ds4_server.sh,follow_run.sh,testnames.py}`,
  `local-code-writer/scripts/lang/{js.sh,php.sh}` (copies)
- Create: `local-test-writer/scripts/sync_shared.sh`, `local-code-writer/scripts/sync_shared.sh`
  (the same file)
- Test: `$CLAUDE_JOB_DIR/tmp/sync/check.sh`

**Interfaces:**
- Produces: the state-folder default in both files becomes
  `STATE=${LTW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$(basename "$(dirname "$SCRIPT_DIR")")}`
  (for `follow_run.sh`, define `SCRIPT_DIR` first as the runner does). In `local-test-writer`
  it still gives `~/.local/state/local-test-writer`.
- Produces: `sync_shared.sh [--take FILE]`. It finds the other skill as the sibling folder
  (`local-test-writer` or `local-code-writer`, the one it is not in). Shared list, one place
  at the top of the script: `apply_blocks.py aider_entry.py ds4_server.sh follow_run.sh
  testnames.py lang/js.sh lang/php.sh sync_shared.sh`. Runner pair, "compare by hand":
  `run_aider_tests.sh` and `run_green.sh`. Output: one line per shared file, `same` or
  `DIFFERS`, the `diff -u` of each one that differs, then the runner pair's `diff -u` under
  the heading `runners (they differ by design; compare by hand)`. Exit 0 when every shared
  file matches, 1 when one differs, 0 with `note: <sibling> not found; nothing to compare`
  when the sibling is missing. `--take FILE` copies the sibling's copy of FILE (one of the
  shared list, else exit 2) over this skill's copy and prints `took FILE from <sibling>`.

- [ ] **Step 1: Write `sync/check.sh`** with these checks, on a copy of both skill folders
  under `$CLAUDE_JOB_DIR/tmp/sync/`:
  1. all shared files equal: exit 0, every line `same`;
  2. one line added to `local-code-writer/scripts/apply_blocks.py`: exit 1, a `DIFFERS`
     line for `apply_blocks.py`, and its diff;
  3. `--take apply_blocks.py` run from `local-test-writer`: the two copies match again, exit 0
     on the next plain run;
  4. `--take run_green.sh`: exit 2;
  5. the sibling folder removed: exit 0, the `note:` line;
  6. `follow_run.sh --path` and `ds4_server.sh status` in the copied `local-code-writer`
     with `LTW_STATE_DIR` unset and `XDG_STATE_HOME=$CLAUDE_JOB_DIR/tmp/sync/state`: the paths
     they print end in `/local-code-writer`; in `local-test-writer`, in `/local-test-writer`.
- [ ] **Step 2: Run it; expected: every check fails** (no script, no copies).
- [ ] **Step 3: Make the two state-folder edits, copy the shared files, write `sync_shared.sh`**
  in `local-test-writer/scripts/`, then copy it to `local-code-writer/scripts/`.
- [ ] **Step 4: Run `sync/check.sh`, `bash -n` on every changed script; expected: all pass.**
  Then run `sync_shared.sh` in the real repo: exit 0 except the runner pair (Task 2 adds
  `run_green.sh`).

### Task 2: `run_green.sh`

**Files:**
- Create: `local-code-writer/scripts/run_green.sh` (from `local-test-writer/scripts/run_aider_tests.sh`)
- Test: `$CLAUDE_JOB_DIR/tmp/green/check.sh` (fake harness)

**Interfaces:**
- Consumes: the shared files of Task 1 (same names, in `$SCRIPT_DIR`).
- Produces: `run_green.sh` with the runner's arguments minus `--agent`, `--max-turns`,
  `--red-lint-ok`, `--lang none` and `--backend ollama` (refused with exit 2 and a line saying
  ds4 and aider only); `--backend openai` is the default. Kept: the guard and watcher, the
  brief check, `--fix-cmd`, `--test-cmd`, `--test-dir`, `--timeout`, `--ds4-dir`,
  `--keep-server`, the placeholder and reasoning-comment scans, `apply_blocks.py` recovery,
  the report and its exit codes (0, 2, 3, runner error). Removed: the test count and "no test
  added", `review_stats.py`, the existing-test check, `FIX_EXPECTED_RE`, the pi branch, the
  Ollama branch. Added: exit 2 with `--write <path> is named like a test file; tests stay
  read-only` (a `--write` path missing from `testnames.py check`'s output), exit 2 with
  `--test-cmd is required: the tests are the check`, and the finding
  `tests still failing: test command exit <rc> (test-output.txt)`. Report title
  `# local-code-writer run`; the report drops "tests added", "existing tests changed as the
  brief asked" and "the model's version of each test file", and keeps the model's version of
  each source file in `OUT/model/` for the review. State folder: as in Task 1.

- [ ] **Step 1: Build the fake harness** in `$CLAUDE_JOB_DIR/tmp/green/`: a git repo with
  `src/sum.ts` (`export function sum(a: number, b: number): number { return 0 }`) and
  `src/sum.test.ts` (expects `sum(2, 3)` to be `5`), committed; a fake `aider` (from
  `$CLAUDE_JOB_DIR/tmp/fix/bin/aider`) with modes `green-ok` (rewrites `return 0` to
  `return a + b`), `green-touch-test` (edits `src/sum.test.ts`) and the default (no change);
  the server: start `$CLAUDE_JOB_DIR/tmp/fakeoai-tools/server.py 18767 <logdir>` (it
  answers `/v1/models` with `fake-model`, `context_length` 32768), set
  `OPENAI_API_BASE=http://127.0.0.1:18767/v1`, pass `--model fake-model --num-ctx 32768`,
  and leave `--ds4-dir` out (the runner uses a server that already answers); the fake
  `aider` on the `PATH` makes the edits, so the server only has to answer the model check.
  Stop the server at the end of `check.sh`.
- [ ] **Step 2: Write `green/check.sh`**:
  1. `--write src/sum.test.ts --test-cmd true`: exit 2, `named like a test file`;
  2. `--write src/sum.ts` and no `--test-cmd`: exit 2, `--test-cmd is required`;
  3. default mode, `--write src/sum.ts --test-cmd 'grep -q "a + b" src/sum.ts'`: exit 0,
     Findings has `tests still failing: test command exit 1`;
  4. `green-ok`, same command: exit 0, Findings `none`, title `# local-code-writer run`, no
     line `tests added`;
  5. `green-touch-test`, `--test-cmd true`: exit 3, report starts `FAILED`, lists
     `src/sum.test.ts`;
  6. `--agent pi`: exit 2; `--red-lint-ok x`: exit 2;
  7. `green-ok` with `--fix-cmd` printing one `no-unsafe-assignment` error line (the old
     harness's `bin/fakelint`): Findings has `1 error(s) left after --fix-cmd`;
  8. with no `local-test-writer` folder next to the copy of `local-code-writer`: check 4
     passes the same.
- [ ] **Step 3: Run it; expected: every check fails** (no `run_green.sh`).
- [ ] **Step 4: Write `run_green.sh`** from the runner, removing and adding what the
  Interfaces list. Keep its header usage block accurate (printed by `sed -n '2,<last header
  line>p'`).
- [ ] **Step 5: Run `green/check.sh`, `bash -n run_green.sh`, and `sync_shared.sh` in both
  skills; expected: all pass, shared files `same`, the runner pair under "compare by hand".**

### Task 3: the GREEN brief template

**Files:**
- Create: `local-code-writer/assets/brief-template.md`

**Interfaces:**
- Consumes: the brief check of `run_green.sh`: the line `You may edit ONLY these files: <each
  --write path in backticks>` must match `--write`.
- Produces: placeholders `{{TASK_NAME}}`, `{{WRITE_FILES}}`, `{{GROUP}}`, `{{PLAN_FILE}}`,
  `{{PLAN_SECTION}}`, `{{TEST_FILES}}`, `{{PER_FILE}}`, `{{FACTS}}`, `{{LANGUAGE_RULES}}`,
  `{{STYLE_FILE}}`, used by Task 4's `SKILL.md`.

- [ ] **Step 1: Write the template.** Rules, each with its reason: answer with the edits now,
  in this reply; edit only `{{WRITE_FILES}}` (an edit to a test fails the run); make
  `{{TEST_FILES}}` pass and write no code no test asks for; never a coverage-ignore comment;
  follow `{{PER_FILE}}` exactly (per file: signatures, messages, call order, as code); no
  placeholder, `TODO` or "not implemented" stub; no cast or non-null assertion to silence the
  type checker; no thinking aloud in comments. Sections: "## The task", "## Per file",
  "## Facts", "## When you are done" (each file changed and the tests it makes pass). A
  "How to fill this" comment for every placeholder.
- [ ] **Step 2: Check it:** no U+2014; fill it for the harness's `src/sum.ts` and run check 4
  of Task 2 with it as `--brief`: the brief check passes.

### Task 4: `SKILL.md`, `README.md` (both skills), `references/`

**Files:**
- Create: `local-code-writer/SKILL.md`, `local-code-writer/README.md`,
  `local-code-writer/references/lessons.md`, `local-code-writer/references/findings.local.md`
- Create: `local-test-writer/README.md`

**Interfaces:**
- Consumes: Tasks 1-3.

- [ ] **Step 1: Write `local-code-writer/SKILL.md`.** Frontmatter `name: local-code-writer`;
  a `description` that says what it does and when to use it (the GREEN step of a planned task
  whose RED tests exist; to let a local model write production code; not for writing tests,
  not for planning). Body, from the design, in this order: what it is; Start (the `lcw-log`
  block); Step 1 prerequisites (ds4 and aider install, the `lcw-log` link, written here in
  full); Step 2 RED coverage (the coverage map and its example, the RED run, the grep of
  existing tests); Step 3 worth it (about 60 source lines, the exact sentence "It is better
  that Claude writes this task.", the estimate, then wait); Step 4 split into groups (one or
  two source files, dependency order); Step 5 per group (brief, the user's go, the command
  below, the check); Step 6 after a failed run (fix plan or brief first; then size only; 18
  received tokens per second, about 10x the code; small = 1-2 files, about 50 lines, 10
  minutes; both estimates and the recommendation, then wait); Step 7 green means (with the two
  RED-gap cases); Step 8 the run report form; Step 9 record. Command block:

  ```bash
  bash ~/.claude/skills/local-code-writer/scripts/run_green.sh \
    --ds4-dir <ds4 checkout> --model qwen3.8-flash-next-reasoner --num-ctx 131072 \
    --brief <brief.md> --write <source file> [--write ...] --read <path> [--read ...] \
    --fix-cmd '<formatter and lint --fix on the source files>' \
    --test-cmd '<command that runs this group's tests>' --test-dir <dir>
  ```
- [ ] **Step 2: Write `README.md` in both skills**, for people and agents, speak-simple: what
  the skill does (two sentences); its files and what each is for; the twin skill and the
  files they share; the sync script: what drift is, with the `apply_blocks.py` fix of
  2026-11-13 as the example, when to run `bash scripts/sync_shared.sh` (after any change to a
  shared file, before a commit), what it prints, how `--take` works, and that the runners
  differ by design. The two READMEs share the sync section word for word.
- [ ] **Step 3: Write `references/lessons.md`** (the reasoner evidence table, the per-file
  plan pattern, the time formula, an empty "Lessons not yet rules"; under 3 KB) and
  `references/findings.local.md` (header: the run log, grep it, never read it whole; one entry
  dated 2026-11-15 pointing to the code runs in `local-test-writer/references/findings.local.md`,
  entries 2026-11-06, 2026-11-09, 2026-11-10, 2026-11-13).
- [ ] **Step 4: Check:** no U+2014 in any new file; no project names in `SKILL.md`, both
  `README.md`, the template and `lessons.md`; every template placeholder named in `SKILL.md`;
  `local-code-writer/SKILL.md` names no path inside `local-test-writer`.

### Task 5: scenario check

**Files:**
- Test: `$CLAUDE_JOB_DIR/tmp/green-q/`

- [ ] **Step 1: Write six scenarios and a rubric:** (a) a 40-line task: the skill says "It is
  better that Claude writes this task." and waits; (b) a plan item with no RED test: stop,
  name it, ask who writes it; (c) a 6-file task: groups of 1-2 files in dependency order, one
  go per run; (d) a failed run, 2 red tests in one file, retry about 5 minutes: recommend a
  local retry, wait; (e) a failed run, wrong logic in 4 files: recommend Claude, wait; (f)
  every test green, one uncovered line: a RED gap; Claude removes the line or names the
  missing test.
- [ ] **Step 2: Two Sonnet subagents answer from `SKILL.md` only; an Opus subagent grades
  blind.** Expected: every rubric line met by both. A line both miss is a gap in `SKILL.md`:
  fix it, rerun that scenario.
- [ ] **Step 3: Report to the owner; wait for "committa".**
