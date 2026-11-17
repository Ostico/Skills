# local-code-writer

A local reasoning model writes the production code of a planned task, the code that makes its
failing tests pass. Claude checks before the runs that the tests cover the whole plan, splits
the task into small groups of files, and reviews each run.

The model runs on ds4 (a local model server) through aider (a coding agent). A guard around
each run keeps the tests read-only: an edit to any file outside the run's source files fails the
run and puts the repo back as it was.

## How to use it

Ask Claude for the GREEN step of a planned task whose failing tests exist, or to let the local
model write the code. Claude asks for a go before each run, because a run takes the GPU and
about 48 GB of memory. While a run works, follow it with `lmw-log`, one command for both skills:

```bash
bash ~/.claude/skills/local-code-writer/scripts/install_lmw_log.sh   # once: makes ~/.local/bin/lmw-log
lmw-log              # the latest run of either skill, live
```

Each run writes a folder under `~/.local/state/local-code-writer/runs/` with the brief, the
model's reply (`run.log`), the diff (`code.diff`) and `report.md`.

## Files

- `SKILL.md`: the steps Claude follows.
- `assets/brief-template.md`: the brief each run sends to the model.
- `scripts/run_green.sh`: the runner. It runs aider once inside the guard, runs the tests and
  writes the report.
- `scripts/` (the other files): helpers shared with `local-test-writer`, below.
- `references/lessons.md`: the measured lessons, short. Claude reads it first.
- `references/findings.local.md`: the run log, one dated entry per run. It stays local
  (`.gitignore` keeps it out of the repo), because it names the projects the runs were
  measured on.
- `design.md`, `plan.md`: the design the skill was built from and its build plan.

## Shared files and the sync script

`local-test-writer` and `local-code-writer` are twin skills. The first hands the failing tests of
a task (the RED step) to a local model; the second hands the code that makes them pass (the
GREEN step). Each skill keeps its own copy of the helper scripts they share, so either one works
when the other is not installed. These files are shared, in `scripts/`:

- `apply_blocks.py`: applies the edit blocks of a model's reply from `run.log` when aider
  dropped them;
- `aider_entry.py`: starts aider so it never asks to add a file to the chat;
- `ds4_server.sh`: starts, stops and checks the local ds4 model server;
- `follow_run.sh`: follows the latest run of either skill while it works (`lmw-log`);
- `install_lmw_log.sh`: installs `lmw-log`, a link in `~/.local/bin` to this skill's
  `follow_run.sh`;
- `testnames.py`: tells test files from source files by their names;
- `lang/js.sh`, `lang/php.sh`: the language profiles of the runner;
- `sync_shared.sh`: the sync script itself.

The cost of two copies is drift: a fix made to one copy and not to the other. Example: on
2026-11-13 `apply_blocks.py` learned to skip aider's own report of failed edit blocks. Without a
check, only one skill would have the fix, and the other would apply the report's blocks a second
time.

`sync_shared.sh` is the check. Run it after any change to a shared file, and before a commit:

```bash
bash scripts/sync_shared.sh
```

It finds the twin as the folder next to this skill's folder, then prints one line per shared
file, `same` or `DIFFERS`, and the `diff -u` of each file that differs. It exits 0 when every
file matches and 1 when one differs. When the twin is not installed it prints
`note: <twin> not found; nothing to compare` and exits 0.

To take the twin's copy of one file, after reading its diff:

```bash
bash scripts/sync_shared.sh --take apply_blocks.py
```

It copies the twin's file over this skill's copy and prints `took apply_blocks.py from <twin>`.
A name outside the shared list exits 2.

The runners differ by design: `run_aider_tests.sh` writes tests, `run_green.sh` writes code. The
script prints their diff under `runners (they differ by design; compare by hand)` and never
counts it as drift. A fix to the part they have in common (the guard, the watcher, the brief
check, the report) goes into both by hand.

`ds4_server.sh` takes the state folder from the name of the skill folder it sits in:
`~/.local/state/local-test-writer` or `~/.local/state/local-code-writer`, so the same file works
in both skills. `follow_run.sh` (the `lmw-log` command) reads both folders and follows the run
that started last. `LTW_STATE_DIR` sets one folder for either script.
