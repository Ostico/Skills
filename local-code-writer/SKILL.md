---
name: local-code-writer
description: Hand the GREEN step of a planned task to a local reasoning model (ds4 driven by aider): the model writes the production code that turns the task's failing tests green, one small group of source files per run, inside a guard that keeps the tests read-only and undoes any edit outside the given files; Claude checks the plan's test coverage before and reviews each run after. Use when the RED tests of a planned task exist and the code is still to write, when asked to let a local or free model write production code, or to offload coding from Claude to ds4. Not for writing tests, not for planning a task, and not for running the project's existing suite.
---

# Local code writer

A local reasoning model writes the GREEN step of a task: the production code that makes the
task's failing tests pass. Claude does the thinking around it. Before the runs, Claude checks
that the tests cover the whole plan and splits the task into small groups of files. After each
run, Claude checks the result. The code is most of a task's output tokens; on the local model
they cost GPU time only.

Terms:
- RED tests: the failing tests of a task, written before the code exists.
- reasoner: the local model with thinking on, `qwen3.8-flash-next-reasoner` on the ds4 server
  (a local OpenAI-compatible server).
- runner: `scripts/run_green.sh`. It runs aider (a coding agent) once, inside a guard. The
  guard undoes every edit outside the `--write` files and fails the run (exit 3) when the model
  edits any other file, a test file included.
- group: one or two source files written by one run.

Read `references/lessons.md` first: the measured lessons, in short.
`references/findings.local.md` is the run log behind them, one dated entry per run: never read
it whole; search it (`grep -n`) for one past run or for a lesson's evidence. It stays local
(`.gitignore` keeps it out of the repo) because it names the projects the runs were measured
on; the lessons and the rules never do.

## Start: show how to follow the runs

Every time this skill starts, your first message to the user contains this block, as it is:

```
Follow the local model while it runs:
  lmw-log            the latest run, live: stage, the reply as it streams, then the report
  lmw-log --path     the full path of the latest run's log
  lmw-log --list     past runs
  tail -f ~/.local/state/local-code-writer/current/run.log
```

When `command -v lmw-log` finds nothing, add the line that installs it (Step 1). Add the
the server's log too: the runner prints its path on the `ds4 log:` line, or
`bash ~/.claude/skills/local-code-writer/scripts/ds4_server.sh log` finds it, whichever skill started the
server. Its speed lines are only there.

## Step 1: Prerequisites (once per machine)

- ds4 (github.com/antirez/ds4) serving `Qwen3.8-Flash-Next-Q2.gguf`. It needs 64 GB of RAM and
  about 140 GB on a local SSD: the weights are larger than RAM and stream from the disk. In its
  checkout:

  ```bash
  make                                   # build
  ./download_model.sh qwen38-q2          # 137 GiB, once; rerun to resume
  ```

- aider on Python 3.12 (3.13 crashes on `audioop`):
  `uv tool install --force --python 3.12 aider-chat`.
- The `lmw-log` command, to follow a run (one command for this skill and its test-writing
  twin): `bash ~/.claude/skills/local-code-writer/scripts/install_lmw_log.sh` (it links
  `~/.local/bin/lmw-log` to this skill's `scripts/follow_run.sh`).

The runner starts and stops the server itself (`--ds4-dir`, Step 5). By hand, from anywhere:

```bash
S=~/.claude/skills/local-code-writer/scripts
bash $S/ds4_server.sh up --dir <ds4 checkout>   # or DS4_DIR=<ds4 checkout>
bash $S/ds4_server.sh status
bash $S/ds4_server.sh down                      # it holds about 48 GiB until stopped
```

`up` starts `ds4-server` with `--ctx 131072` on port 8000, waits until `/v1/models` answers
(under a minute) and prints the memory plan. It leaves a server already answering as it is,
and refuses when an Ollama model of 2 GB or more is loaded or another process holds the port.

- The window is the server's `--ctx`, fixed when it starts. The runner's `--num-ctx` must be
  the same number; the runner checks it against the `context_length` the server reports.
- Thinking is chosen by the model alias: `qwen3.8-flash-next-reasoner` has it on. Use that
  alias: the measured code runs all used it.
- The runner sends Qwen's sampling for thinking mode: temperature 0.6, top_p 0.95, top_k 20,
  min_p 0. aider alone sends temperature 0, and greedy thinking looped: one 224-line block 34
  times in 68 minutes, no edit.
- A prompt longer than the window is refused before any work, and aider still exits 0; a reply
  that runs out of room stops with no error, and aider applies none of its edits. The runner
  reports both as findings. Keep the brief and the `--read` files well under the window: the
  reasoner's thinking needs room.

A run takes the GPU and about 48 GB, often for 5 to 40 minutes. Before a run, check what is
loaded: `ollama ps`, `pgrep -lx ds4-server`, `lsof -iTCP:8000 -sTCP:LISTEN`. When `up` refuses
because a large Ollama model is loaded, ask the user before stopping it (`ollama stop
<model>`).

## Step 2: Check that the RED tests cover the whole plan

The skill starts only when every idea, hypothesis and assertion of the plan has at least one
test that fails today for the right reason: the missing code, not a syntax error or a wrong
import. Whoever wrote the tests (another skill, Claude or the user), check this yourself.

1. Write a coverage map: one line per item of the plan, with the test or tests that cover it.

   ```
   - "a name longer than 64 characters is refused" -> `a 65-character name is refused`
   - "the retry delay doubles after each refusal" -> `delays are 100, 200 and 400 ms`
   - "a closed log refuses appends" -> MISSING
   ```

2. An item marked MISSING stops the skill. Name the missing tests and ask the user who writes
   them: a local test-writing skill, Claude, or the user. Start again from this step when they
   exist.
3. Run the RED tests. Each one must fail on the missing code. A test that passes already, or
   fails on a syntax error or a wrong import, goes back to whoever wrote it.
4. Grep the existing tests for each signature, field or behaviour the task changes. An old test
   that the task will break goes to the user now, with the change it needs; the model may not
   touch it.

Line and branch coverage cannot be measured before the code exists; Step 7 measures it.

## Step 3: Check that a local run is worth it

The local path has a fixed cost for Claude: the per-file plan, the briefs and the review. On a
small task that cost is larger than writing the code. Measured: a task of about 40 source lines
cost Claude about 67k tokens through local runs, against an estimated 25 to 30k to write it
directly.

Estimate the source lines and files the task adds or changes. When it is about 60 source lines
or fewer, write to the user, in these words: "It is better that Claude writes this task." Give
the estimate: the source lines and files, and Claude's tokens for each path. Then wait for the
user's choice. Over the threshold, give the same estimate and go on.

## Step 4: Split the task into groups

Split the task's source files into groups of one or two files each, in dependency order: a file
comes after the files it imports. Each group is one run, with its own brief and the RED tests
that its files make green. Small runs with a check after each gave the best measured results;
one large run spent the tokens the skill is meant to save.

Example: a task adds `src/types.ts`, `src/store.ts` (imports types), `src/api.ts` (imports
store) and `src/cli.ts` (imports api). Groups: 1 `src/types.ts` and `src/store.ts`; 2
`src/api.ts`; 3 `src/cli.ts`.

## Step 5: For each group, in order

Each group goes through the same four steps: write its brief, get the user's go, run the
reasoner once, check the run. The next group's brief starts only when this group's tests, type
check and lint are green, because the next group reads the files this one wrote. One type error
may stay: a group that changes a signature breaks its caller until a later group writes that
caller. Name that error in the brief's facts (file and message), and accept that one error
only; any other one stops the next brief.

Example: group 3 adds `prompt` and `check` to `tools/index.ts`; `index.ts`, written by group 4,
fails the type check on the missing fields until group 4 runs. Group 3 is green with that one
error. When the user
gives one go for "the code", tell the user it covers the first run only, and ask again before
each next run.

### 5.1 Write the brief

Copy `assets/brief-template.md` and fill every placeholder; its closing comment says how, and
the comment goes before the run:
- `{{TASK_NAME}}`, `{{GROUP}}`: the task's name and "group <n> of <total>: <files>";
- `{{WRITE_FILES}}`: the group's source files, in backticks. The runner stops before the run
  when this line differs from `--write`;
- `{{PLAN_FILE}}`, `{{PLAN_SECTION}}`: the plan and the task's section;
- `{{TEST_FILES}}`: the RED test files this group turns green;
- `{{PER_FILE}}`: for each source file, as code, the signatures, the messages and the order of
  the calls. This is the condition for success: with it the reasoner wrote correct code; with a
  loose plan it reached green tests with code Claude then rewrote;
- `{{FACTS}}`: only what the plan, the tests and the `--read` files do not say;
- `{{LANGUAGE_RULES}}`: the project's style or language rules for this code, or nothing;
- `{{STYLE_FILE}}`: one source file in the house style.

Pass with `--read`: the plan section, the group's test files, the sources the code imports, the
files earlier groups wrote and the style file. Never pass a test file with `--write`: the
runner refuses it (exit 2), so the model cannot change a test to make it pass. It refuses a
test helper, mock, fixture or test config too (a path under `test/`, `tests/`, `__mocks__/`,
`fixtures/` and the like, or a file such as `vitest.config.ts`): when the plan changes one,
change it yourself before the run. The same holds for test support whose types follow the code
the group changes (a fake built from an interface the group extends): update it before the
run, or the group's tests fail on the fake.

### 5.2 Get the user's go

A run takes the GPU. Ask the user's go for each run, never carried over from an earlier one.
Name the backend (ds4), the model alias, the window and the group.

### 5.3 Run the reasoner once

```bash
bash ~/.claude/skills/local-code-writer/scripts/run_green.sh \
  --ds4-dir <ds4 checkout> --model qwen3.8-flash-next-reasoner --num-ctx 131072 \
  --brief <brief.md> --write <source file> [--write ...] --read <path> [--read ...] \
  --fix-cmd '<formatter and lint --fix on the source files>' \
  --test-cmd '<command that runs this group's tests>' --test-dir <dir>
```

- `--test-cmd` is required: it runs after the model, and while it fails the report says
  "tests still failing". `--test-dir` is the folder the commands run in (their working
  directory), relative to the repo root.
- The `--read` files must be inside the repo. Keep the brief outside it (for example in
  `~/.local/state/local-code-writer/`), so the run leaves no new file in the project.
- Run it in the background. Its first lines name `OUT`, the run's folder; take it from the
  `out:` line.
- aider's own test loop stays off (the runner sets `--no-auto-test`): each retry would be
  another reasoner turn.
- A run always goes to its end: never stop, kill or restart it. The runner stops one itself
  when the reply loops (the same block of 50 lines or more three times in a row, each copy
  right after the one before), with the finding "thinking loop". The same code drafted,
  drafted again and then answered is the normal shape of a thinking reply, and is no loop.
  Never edit the repo while it runs: the watcher cannot tell your edit from
  the model's, and fails the run.

Exit codes: 0 the report is written (read its Findings); 2 the run did not start (the message
says why); 3 the model or `--fix-cmd` edited outside `--write`, the repo is back as it was and
`report.md` says FAILED; any other code is a bug of the runner, and `report.md` says RUNNER
ERROR with the line.

### 5.4 Check the run

1. Read `<OUT>/report.md`. Read `run.log` and `chat.md` raw, with the Read tool, never through
   a shell filter that shortens output: an edit block cut short looks complete there.
2. When a finding says edit blocks are missing (aider applied none, or a retry sent none),
   recover the complete blocks from the log, from the repo root:

   ```bash
   python3 ~/.claude/skills/local-code-writer/scripts/apply_blocks.py <OUT>/run.log <each --write file>
   ```

   It reports each block as applied, already in the file, or not found.
3. A "thinking loop" finding: the run wrote no code. Go to Step 6; a retry of the same brief
   samples another path.
4. Run the group's tests, the type checker and the linter on its files.
5. Green: review the diff (`<OUT>/code.diff`; the model's version of each file is in
   `<OUT>/model/`), fix what the review finds, then move to the next group.
6. Not green: go to Step 6.

## Step 6: After a failed run, recommend and wait

First, when the failure comes from the plan or the brief (a wrong fact, a missing signature),
fix that. It is a precondition of any next step, and it does not decide between the two
options: a fixed brief may well give a good local run.

Then only the size of the fix decides. Estimate:
- the fix: the failing tests and their cause, the files and the lines to change;
- the local retry: a narrow brief (only the failing tests and the files to change) and its run
  time. Time = expected received tokens / 18 per second. Received tokens are about 10 times the
  tokens of the code, since most of them are thinking. Example: 50 lines of code are about
  500 tokens, so about 5,000 received tokens, about 5 minutes;
- Claude's own cost to finish: the tokens to read the code, change it and run the checks.

Recommend:
- a local retry when the fix is small: 1 or 2 files, about 50 changed lines or fewer, a retry
  of 10 minutes or less. Example: 2 tests red on one edge case in one file, a retry of about 5
  minutes;
- finishing with Claude when the fix is larger. Example: wrong logic across 4 files, or a retry
  of 40 minutes.

Show the user both estimates and the recommendation, then wait for the user's choice. A retry
follows Step 5 like a first run, with its own go; after it fails, evaluate again. When Claude
finishes a group, the next group can still go to the local model.

## Step 7: Green means

After the last group:
- every test of the task passes, the RED ones and the ones that existed before;
- the type checker and the linter pass on the changed files;
- line and branch coverage is 100% on the lines the runs added or changed, and the project's
  own coverage gate passes when it has one. Run the project's test command with its coverage
  option and read the changed lines in the coverage report.

Two cases are gaps of the RED step, not failures of the model. They do not go to Step 6:
- Coverage short with every test green. A line that no test asks for: remove it. A test missing
  from RED: name it, and the user chooses who writes it, as for a MISSING item in Step 2. A
  coverage-ignore comment the model added (`/* istanbul ignore */`, `@codeCoverageIgnore`) is a
  finding: remove it.
- An old test fails because the task changes the behaviour it checks, and the grep of Step 2
  did not find it. Change that test in review, as the plan's behaviour requires, and record it
  as a RED gap.

## Step 8: Report each run

The run report, in this form:

```
Status: <GREEN | GREEN AFTER FIXES | NOT GREEN>
## Local code run: <task>, group <n> of <total>
Follow: lmw-log | log: <OUT>/run.log
Model <alias> on ds4, <seconds> s, tokens <sent> sent / <received> received
Files: <each --write file, with lines added and removed>
Runner findings: <none, or each line of report.md's Findings, with how you fixed it>
Tests: <passing>/<total> of this group; type check <ok | errors>; lint <ok | errors>
Fixed in review: <one line per fix: file, what was wrong, the fix>
RED gaps: <none, or each gap and what was done>
Next: <the next group, or the Step 6 recommendation and its estimates>
```

The numbers come from `report.md` and the commands you ran, not from estimates.

A failed run (exit 3), in this form instead:

```
Status: FAIL (edit outside the allowed files)
## Local code run: <task>, group <n> of <total>
Follow: lmw-log | log: <OUT>/run.log
By: <the model | --fix-cmd>, after <seconds> s; paths: <each path report.md lists>
What it changed: <one line per path, from OUT/violations/>
Repo: back as it was before the run
```

## Step 9: Record the run

Append a dated entry to `references/findings.local.md` (create it when missing): the run
report's numbers, the brief's size, the group's files, and what the fixes had in common. When
the run teaches something that is not yet a rule in this file or the brief template, add one
line to `references/lessons.md` too, ending with the entry's date ("(findings <date>)"). The
lesson line stays generic: names from the project belong in the run log only.

## Shared files

This skill keeps its own copy of the helper scripts it shares with its test-writing twin, so it
works alone. After a change to one of them, run `bash scripts/sync_shared.sh`; `README.md`
says what it prints.
