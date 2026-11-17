# local-code-writer: design

## What it is

`local-code-writer` is a skill for the GREEN step of a planned task. A local reasoning model
writes the production code that makes the task's failing tests pass. Claude plans the task
before the skill starts and reviews the result after the run. The skill hands the coding to the
local model, so Claude spends its tokens on design and review.

Terms used below:
- RED step: the failing tests of a task, written before the code exists.
- GREEN step: the code that makes those tests pass.
- reasoner: a local model with thinking on. The measured one is `qwen3.8-flash-next-reasoner`
  on the ds4 server (a local OpenAI-compatible server).
- runner: `local-code-writer/scripts/run_green.sh`, this skill's copy of `local-test-writer`'s
  runner. It runs aider (a coding agent) once inside a guard. The guard undoes every edit
  outside the `--write` files and fails the run (exit 3) when the model edits any other file.

It is the twin of `local-test-writer`, which hands the RED step to a local model.

## Why

The owner wants Claude as the main model: Claude designs the task and reasons about it, which
costs few tokens. A local model writes the tests, then the code. Writing code takes most of
the output tokens of a task; on the local model they cost GPU time only.

Measured runs back the idea (`local-test-writer/references/findings.local.md`, entries of
2026-11-06, 2026-11-09, 2026-11-10 and 2026-11-13). All used the runner with the source files in
`--write` and the reasoner on ds4:

| Run | Files | Time | Tokens received | Result |
|---|---|---|---|---|
| plan with signatures and call order per file | 2 | 352 s | 6.4k | 6 small fixes (comment wraps) |
| same plan style, 4 of the files new | 6 | 2344 s | 52k | 8 small fixes |
| same plan style | 2 | 1827 s | 39k | 13 small fixes; the one logic fix came from a race in Claude's plan |
| review-fix round, 3 files | 3 | 446 s | 6.1k | exactly the brief, tests green first time |
| second review-fix round, 3 files | 3 | 614 s | 10k | exactly the brief, one old test needed a change |
| refactor plus a new export, per-file plan | 5 test files | 1199 s | 20k | 121 tests green on the first run, no logic error |
| stateful I/O module, loose plan | 4 | 2646 s | 58k | tests green, but casts and below the project's bar: Claude rewrote it |
| PHP task, plan without per-file detail | | 39 min | about 38k, mostly thinking | about 4k tokens of code: not worth it |

The pattern: the reasoner writes correct code when the plan gives, for each file, the
signatures, the messages and the order of the calls as code, and the RED tests exist. With a
loose plan it reaches green tests with code Claude then rewrites, which costs the tokens the
skill is meant to save. End to end the reasoner produced about 14 to 22 received tokens per
second, prefill included.

## Goals

- Small reasoner runs, one per group of source files in dependency order, write the code that
  turns every RED test of the task green. Each run is checked before the next one starts:
  small runs with a check after each gave the best measured results.
- The tests stay as they are: the model may change only the task's source files.
- After a failed run, the skill tells the user whether a second local run or Claude is the
  better way to finish, with its estimates, and waits for the user's choice.
- Claude's tokens go to the plan, the brief and the review; Claude writes code only when the
  user chooses that.

## Non-goals

- Writing tests. That is `local-test-writer`, or Claude, or the user.
- Planning the task. Claude plans it before the skill starts.
- A loop of reasoner runs. Every run, the next group or a retry, needs the user's go.
- Code review by the local model.

## Anti-goals

These would make the skill a failure even if the code turned green:
- The model changes a test to make it pass.
- Claude spends more tokens fixing the model's code than it would spend writing the code.
- A second run starts without the user's go.
- Code that no test asks for: every new line must be covered by a test.

## Prerequisite: every idea of the plan has a RED test

The skill starts only when the RED tests cover the whole plan, whoever wrote them. Every idea,
hypothesis and assertion of the plan must have at least one test that fails today for the
right reason (the missing code, not a syntax error or a wrong import).

Claude checks this before the run with a coverage map: one line per item of the plan, with the
test or tests that cover it. Example:

```
- "a name longer than 64 characters is refused" -> `a 65-character name is refused`
- "the retry delay doubles after each refusal" -> `delays are 100, 200 and 400 ms`
- "a closed log refuses appends" -> MISSING
```

An item marked MISSING stops the skill. Claude names the missing tests and the user chooses who
writes them (`local-test-writer`, Claude, or the user). The skill then runs the RED tests to
confirm each one fails for the right reason.

Line and branch coverage cannot be measured before the code exists. It is measured after the
run, as part of "green" below.

## Is a local run worth it?

Before any run, Claude estimates whether handing the code off saves Claude tokens. The local
path has a fixed cost for Claude: the per-file plan, the briefs and the review. On a small task
that cost is larger than writing the code directly. Measured: a task of about 40 source lines
cost Claude about 67k tokens through local runs, against an estimated 25 to 30k to write it
(findings 2026-11-10).

When the task is small, the skill says so plainly: "It is better that Claude writes this task."
It gives the estimate (source lines and files, Claude's tokens for each path) and waits for the
user's choice. Starting threshold (Claude's call, to be tuned with runs): about 60 lines of
source code or fewer.

## Steps

1. Show how to follow the runs: the `lmw-log` block (the follow command of both skills).
2. Check the prerequisite above (the coverage map and a RED run of the tests), and grep the
   existing tests for each signature, field or behaviour the task changes.
3. Check whether a local run is worth it (section above).
4. Split the task into groups of one or two source files each, in dependency order: a file
   comes after the files it imports. Each group is one run, with its own brief and the RED
   tests that its files make green.
5. For each group, in order:
   1. Write its brief. It holds, for each source file, the signatures, the messages and the
      call order as code (the condition for success in the measured runs). The plan section,
      that group's RED test files, the sources the code imports and the files earlier runs
      wrote go in `--read`. The group's source files go in `--write`; the test files stay out
      of `--write`, so the guard fails the run if the model edits one.
   2. Get the user's go for the run (it takes the GPU), naming the backend, the model, the
      window and the group. Run the reasoner once. aider's own test loop stays off
      (`--no-auto-test`, as the runner already sets it): each retry would be another reasoner
      turn.
   3. Check the run: that group's tests, the type checker and the linter on its files.
   4. When the group's tests are green: Claude reviews its diff, then moves to the next group.
   5. When they are not green: Claude evaluates and recommends (section below), then waits.
6. After the last group: the whole task's tests, the old tests and the coverage (green means,
   below). Claude reports.
7. Record each run in this skill's own `references/findings.local.md`, and a lesson in
   `references/lessons.md` when it teaches one (the same pattern as `local-test-writer`).

## Green means

- every test of the task passes, the RED ones and the ones that existed before;
- the type checker and the linter pass on the changed files;
- line and branch coverage is 100% on the lines the run added or changed, and the project's
  own coverage gate passes when it has one. An uncovered line is code that no test asks for, or
  a test missing from RED.

Two cases are gaps of the RED step, not failures of the model. They do not go to the
retry-or-Claude choice:
- Coverage short with every test green. A line no test asks for: Claude removes it. A test
  missing from RED: Claude names it, and the user chooses who writes it, as for a MISSING item
  of the coverage map. The model must not add coverage-ignore comments
  (`/* istanbul ignore */`, `@codeCoverageIgnore`); one it added is a finding, and Claude
  removes it.
- An existing test fails because the task changes the behaviour it checks, and the RED brief
  did not list it. Claude changes that test in review, as the plan's behaviour requires, and
  records it as a RED gap. To catch these before the run, the start check greps the existing
  tests for each signature, field or behaviour the task changes.

## After a failed run: retry locally or finish with Claude

First, when the failure comes from the plan or the brief (a wrong fact, a missing signature),
Claude fixes that. This is a precondition of any next step; it does not decide between the two
options. A fixed brief may well give a good local run.

Then only the size of the fix decides. Claude estimates:
- the fix: the failing tests and their cause, the files and the lines to change;
- the local retry: a narrow brief (only the failing tests and the files to change) and its
  run time. Time = expected received tokens / 18 per second. Received tokens are about 10
  times the code's tokens, since most of them are thinking (the PHP run above: about 38k for
  4k of code);
- Claude's own cost to finish: the tokens to read the code, change it and run the checks.

Claude recommends:
- retry locally when the fix is small. Starting thresholds (Claude's call, to be tuned with
  runs): 1 or 2 files, about 50 changed lines or fewer, a retry of 10 minutes or less. Example:
  2 tests red on one edge case in one file, a retry of about 5 minutes;
- finish with Claude when the fix is larger. Example: wrong logic across 4 files, or a retry of
  40 minutes.

Claude shows both estimates and the recommendation, then waits for the user's choice. A
retry follows the same rules as the first run of the group; after it fails, Claude evaluates
again. When Claude finishes a group, the next group can still go to the local model.

## Constraints

- A run takes the GPU: the user's go for each run, never carried over from an earlier one.
- A run always goes to its end: never stop, kill or restart it.
- The skill stays generic: no project names in its rules; they go in its findings only.
- Every file of the skill is in English, with no em-dash character.
- Never edit the repo while a run is going: the watcher cannot tell the edit from the model's.

## Decided by the owner

- The skill covers the GREEN step only.
- The RED tests must cover every idea, hypothesis and assertion of the plan before the run.
- Small runs, one per group of files, each checked before the next; one reasoner run per go.
- After a failed run the user decides; the size of the fix is the only criterion for the
  recommendation.
- On a small task the skill says plainly that Claude should write it.

## Claude's calls, to check

- The name `local-code-writer` and its place next to `local-test-writer`.
- The thresholds of "small" (1 or 2 files, about 50 lines, 10 minutes).
- Groups of one or two source files per run, in dependency order.
- The "worth it" threshold: about 60 source lines or fewer goes to Claude.
- The time estimate (18 received tokens per second, received tokens about 10 times the code).
- Green includes 100% line and branch coverage on the lines the run added or changed, plus the
  project's own gate.
- A coverage gap with green tests, and an old test the task breaks, are RED gaps that Claude
  handles in review; they are not model failures.
- Its own `findings.local.md` and `lessons.md`, apart from `local-test-writer`'s.
- ds4 and aider only at the start; Ollama and pi later.

## Decided with the owner (2026-11-16)

- One follow command for both skills, `lmw-log` (local model writer), in place of `ltw-log`
  and `lcw-log`: it follows the latest run of either skill.

## Decided with the owner (2026-11-15)

- The skill works on its own, with its own runner copy; no coordinator skill.
- Both skills carry `sync_shared.sh` and a `README.md` for people that names it.

## Standalone, with a sync script

`local-code-writer` works on its own: it needs no other skill installed. It carries its own
copy of the runner tools, cut down to the GREEN step, in `local-code-writer/scripts/`:
- `run_green.sh`: the runner. It starts from `local-test-writer`'s `run_aider_tests.sh` with
  the test-only parts removed (test count, "no test added", `review_stats.py`, the check of
  changes to existing tests, the RED lint allowances). It refuses a `--write` file named like a
  test file and a run without `--test-cmd` (exit 2), and reports "tests still failing" when the
  test command fails;
- shared files, copied as they are: `apply_blocks.py`, `aider_entry.py`, `ds4_server.sh`,
  `follow_run.sh`, `install_lmw_log.sh` (installs `lmw-log`), `testnames.py`, `lang/js.sh`,
  `lang/php.sh`;
- `sync_shared.sh`, the sync script (below).

Backend and agent: ds4 and aider only, the only measured pair for code. Ollama and pi can come
later, once runs measure them.

State: its own folder `~/.local/state/local-code-writer`. The follow command, `lmw-log`, serves
both skills. `ds4_server.sh` takes the state folder from the name of the skill folder it sits
in, so the same file works in both skills; `follow_run.sh` reads both state folders. The ds4 server itself is
shared: `ds4_server.sh` uses a server that already answers and leaves it running, and a
runner's EXIT trap stops only the server its own `up` started (`down --only-started`).

The cost of the copy is drift: a fix to a shared file must reach both skills. Example: the
`apply_blocks.py` fix of 2026-11-13 would have been needed in both. `sync_shared.sh` is in
both skills and does the check:
- with no argument, it lists each shared file that differs from the other skill's copy, with
  the diff; it exits 0 when all match, 1 when one differs, and 0 with a note when the other
  skill is not installed;
- `--take <file>` copies the other skill's version of one shared file over this one, after
  the diff is read;
- the runners differ by design, so it lists them apart as "compare by hand" with their diff.

Each skill gets a `README.md` for people and agents: what the skill does, how its files fit,
and that `sync_shared.sh` exists, when to run it (after any change to a shared file) and what
it prints. Written in the owner's speak-simple style.

## Left to the builder

- The GREEN brief template.
- How the coverage command is given per project (a `--coverage-cmd`, or the test command with
  its coverage flag).
