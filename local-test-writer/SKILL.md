---
name: local-test-writer
description: Have a local model (Ollama, driven by aider) write the failing tests of a planned task, inside a guard that undoes any edit outside the test files and flags placeholder tests, then review the result before any code is written. Use when asked to let a local or free model write tests, to offload test writing from Claude to Ollama, to run a TDD red step with qwen/gemma/another local coder, or to measure whether a local model can be trusted with tests. Not for writing production code with a local model, and not for running the project's existing suite.
---

# Local test writer

A local model writes the RED step of a task: the failing tests, nothing else. The orchestrating
agent prepares the brief, runs the model inside a guard, and reviews every line before the tests
count. The local model is cheap and private; it is also small, so the design assumes it will try
to break the rules and makes breaking them harmless.

Read `references/findings.md` first: it records what failed before and why each piece here
exists.

## Step 0: Prerequisites (once per machine)

- Ollama with a coding model that supports tools, e.g. `qwen3-coder:30b`.
- aider on Python 3.12 (3.13 crashes on `audioop`):
  `uv tool install --force --python 3.12 aider-chat`.
- Ollama's server environment: `OLLAMA_NUM_PARALLEL=1` (the KV cache multiplies by it).
  Ollama.app reads it only at start.

Running a local model uses the GPU and many GB of memory for minutes: get the user's go for
each run, and say which model and window you will load.

## Step 1: Size the context window

Close or open the apps that will stay open during the run, unload the model, then:

```bash
scripts/ctx_budget.py <model> [--margin-gib 4] [--parallel 1]
```

It prints the memory in use, the model's weights and KV cost per token, and the largest window
for an f16 and a q8_0 KV cache. Pick a window at or under the f16 figure (q8_0 needs
`OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0` on the whole server: ask first, it
changes every model's behaviour). A test-writing run usually needs 30k to 90k tokens.

## Step 2: Pin the window in a model variant

```bash
scripts/make_ctx_variant.sh <base-model> <num_ctx> [name]
```

The variant shares the base weights and keeps its chat and tool format (the script fails if
`RENDERER`, `PARSER` or `TEMPLATE` differ). Pinning matters: a window that changes between
requests makes Ollama reload the model, and Ollama cuts the start of an over-long prompt
without an error.

## Step 3: Write the brief

Copy `assets/brief-template.md` and fill it from the plan:
- the exact files the model may edit, the interfaces it must NOT implement, the test names with
  their exact values, and one finished test copied from the project as the style example;
- never ask the model to run the type checker or the linter: a RED test makes them fail, and a
  small model then "fixes" the source;
- say plainly that a test failing on a missing function is the correct result;
- aider sends the brief once and exits after the reply: the brief must ask for the edits in
  that reply, or the model may only announce what it will do and stop.

## Step 4: Run inside the guard

```bash
scripts/run_aider_tests.sh --brief <brief.md> --model <variant> --num-ctx <N> \
  --write <test file> [--write ...] --read <source the tests use> [--read ...] \
  [--test-cmd '<command that runs only those tests>' --test-dir <dir>] \
  [--timeout 1200] [--out <dir>]
```

What it does: refuses to start if a `--write` file has uncommitted changes; runs aider with no
commits, no shell commands, no `.gitignore` edits and history files kept in the output folder;
kills it at the timeout; then undoes every change outside `--write` (reverts tracked files,
moves new files to `violations/`, reports a pre-dirty file that changed); scans the added lines
for placeholders; runs the test command; writes `report.md`.

Exit codes: 0 clean, 3 edits outside `--write` were undone, 4 suspected placeholders, 5 aider
failed, 6 no test added, 124 timeout. A non-zero exit is a finding about the model, not a reason to rerun
blindly.

## Step 5: Review before the tests count

The guard catches the obvious failures, not weak tests. Read `tests.diff` line by line:
- every test named in the brief exists, with the brief's exact values;
- each one fails for the stated reason (read `test-output.txt`: a missing export or function,
  not a syntax error or a wrong import path);
- no assertion is weaker than the plan asks (`toBeDefined` where a value was given, a missing
  `await`, a try/catch that swallows the failure);
- the existing tests are untouched and still pass.

Fix small defects yourself and note them; if more than one test needs rewriting, discard the
run (`git checkout -- <files>`) and say so.

## Step 6: Record the run

Append a dated entry to `references/findings.md`: model, window, time, guard result, how many
tests survived review unchanged, what had to be fixed. These numbers decide whether the local
model keeps the job.
