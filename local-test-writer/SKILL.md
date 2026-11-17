---
name: local-test-writer
description: Hand the failing tests of a planned task to a local model (Ollama or an OpenAI-compatible local server such as ds4, driven by aider or pi): run the model inside a guard that undoes any edit outside the test files and flags placeholder tests, then review the result before any code is written. Use at the RED step of a planned task, when asked to let a local or free model write tests, to offload test writing from Claude to Ollama or ds4, or to measure whether a local model can be trusted with tests. Not for writing production code with a local model, and not for running the project's existing suite.
---

# Local test writer

A local model writes the RED step of a task: the failing tests, nothing else. Complexity is not
a reason to write them yourself: measured local models write async ordering tests that need
only small fixes (see `references/lessons.md`).

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
  tail -f ~/.local/state/local-test-writer/current/run.log
```

When `command -v lmw-log` finds nothing, add the line that installs it (Step 2). With ds4, add
the server's log too: the runner prints its path on the `ds4 log:` line, or
`bash ~/.claude/skills/local-test-writer/scripts/ds4_server.sh log` finds it, whichever skill started the
server. Its speed lines are only there.

## Step 1: Decide who writes the tests

The local model writes the RED tests of the task; write them directly only when the user says
so. List the tests the plan names for this task and the files they go to: those files are the
run's `--write` files. Split a task into runs of one or two test files each (Step 3: one brief
per run): a brief over more files got the first file's edits and stopped, or no edit at all. A
list of edits to existing tests gets one file per run, or you make the edits by hand before
the run: spread over several files, the model made the first file's edits and stopped.

## Step 2: Prerequisites (once per machine)

Two backends; pick one per machine and say which:
- **ds4** (the default when the machine has it): `Qwen3.8-Flash-Next-Q2.gguf` served by
  `ds4-server` (github.com/antirez/ds4), thinking off through the `qwen3.8-flash-next-nothink`
  alias. About 2.5 times faster than the 27B on Ollama, with tests as good or better
  (`lessons.md`). It needs 64 GB of RAM and about 140 GB on a local SSD: the weights are larger
  than RAM and stream from the disk.
- **Ollama** (the fallback): a dense coding model of about 27B; the default is
  `qwen3.8:27b-q8_0` (30 GB, no streaming).

The mixture-of-experts `qwen3.6:35b-a3b` (3B active parameters) failed on async and
child-process tests; Flash-Next, also mixture-of-experts, did not. Judge a model by its measured runs
(`lessons.md`), not by its architecture.

For both:
- aider on Python 3.12 (3.13 crashes on `audioop`):
  `uv tool install --force --python 3.12 aider-chat`.
- The `lmw-log` command, to follow a run (one command for this skill and `local-code-writer`):
  `bash ~/.claude/skills/local-test-writer/scripts/install_lmw_log.sh` (it links
  `~/.local/bin/lmw-log` to this skill's `scripts/follow_run.sh`).
- Only for `--agent pi` (Step 4): pi on the `PATH`,
  `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` (measured with 1.5.0).

ds4 (in its checkout):

```bash
make                                   # build
./download_model.sh qwen38-q2          # 137 GiB, once; rerun to resume
```

The runner starts and stops the server itself (`--ds4-dir`, below); by hand, from anywhere:

```bash
bash scripts/ds4_server.sh up --dir <ds4 checkout>   # or DS4_DIR=<ds4 checkout>
bash scripts/ds4_server.sh status
bash scripts/ds4_server.sh down                      # it holds about 48 GiB until stopped
```

`up` starts `ds4-server -m gguf/Qwen3.8-Flash-Next-Q2.gguf --ssd-streaming --ctx 131072
--prefill-chunk 1024 --port 8000`, logs to `~/.local/state/local-test-writer/ds4-server.log`,
waits until `/v1/models` answers (under a minute) and prints the memory plan (47.6 GiB). It
leaves a server already answering as it is, and refuses when an Ollama model of 2 GB or more is
loaded (unless `--stop-ollama`; a small embedding model fits beside it) or another process
holds the port.

- `/v1/models` lists `qwen3.8-flash-next`, `-chat` and `-reasoner`, not `-nothink`: the server
  still resolves the `-nothink` alias.
- The window is the server's `--ctx`, fixed when it starts; the runner's `--num-ctx` must be
  the same number (the runner checks it against the `context_length` the server reports).
  `scripts/ctx_budget.py` and `make_ctx_variant.sh` are for Ollama only.
- Thinking is chosen by the model alias, not by a parameter: `qwen3.8-flash-next-nothink` off
  (the default), `qwen3.8-flash-next-reasoner` on. The runner refuses `--think` with this
  backend.
- A prompt longer than `--ctx` is refused (HTTP 400 `context_length_exceeded`, before any
  prefill); aider still exits 0 and writes nothing, so the runner reports it as a finding.
- A reply that runs out of room in `--ctx` stops with `finish_reason: "length"`, with no error;
  aider then applies none of its edits ("has hit a token limit!"), and the runner reports that
  too. Leave the reply room: brief and `--read` files well under the window.

Ollama (the fallback):
- `OLLAMA_NUM_PARALLEL=1` in Ollama's server environment (the KV cache multiplies by it);
  Ollama.app reads it only at start.
- A variant that pins the window and the card's sampling values for the thinking mode in use.
  Thinking off is the default: it ran 3 to 5 times faster with no better tests.

  ```bash
  python3 scripts/ctx_budget.py <model>       # largest window that fits now
  bash scripts/make_ctx_variant.sh qwen3.8:27b-q8_0 122880 qwen3.8-27b-nothink-120k \
    temperature=0.7 top_p=0.8 top_k=20 min_p=0 presence_penalty=1.5 repeat_penalty=1
  ```

  The variant shares the base weights; the script fails if the chat format (`RENDERER`,
  `PARSER`, `TEMPLATE`) changed. A window that changes between requests makes Ollama reload
  the model, and Ollama cuts the start of an over-long prompt without an error.
- Before a run, check `ollama list` for the variant itself, not only `ollama ps`: a deleted
  variant was found missing only when the run was due.

A run takes the GPU and 36 to 48 GB for 5 to 20 minutes: get the user's go for each run, and say
which backend, model and window you will load. A ds4 server and a loaded Ollama model do not
fit together, nor do two large Ollama models. Before a run check what is loaded:
`ollama ps`, `pgrep -lx ds4-server`, `lsof -iTCP:8000 -sTCP:LISTEN`. Then, for ds4, in this
order:
1. With the user's go for the run, run the runner with `--backend openai --ds4-dir <ds4
   checkout>` (Step 4): when the server does not answer, the runner starts it with
   `ds4_server.sh up` (`--ctx` = `--num-ctx`) and stops it when the run ends; a server already
   answering is used and left running. `--keep-server` keeps a started one for the next run.
2. When `up` refuses because a large Ollama model is loaded, ask before stopping it
   (`ollama stop <model>`). The speed lines of a run (`prefill chunk ... avg=`,
   `decoding ... avg=`) are only in the server's log.

## Step 3: Prepare the brief

Read the section of `references/languages.md` for the test files' language: its helpers, brief
rules, review checks and commands add to the steps here. A language without a section: tell the
user, use these steps alone, and treat the run as a measurement (record it, then write the
section).

- Write any test infrastructure the tests need and the project lacks, before the run, in the
  helpers file: anything that talks to a process, a socket, a certificate or a clock. For
  example: a child process that loads the code under test, a cross-process lock, a client that
  trusts the test CA, a request in the protocol each listener speaks (plain HTTP or TLS), a fake
  clock or the code's own clock option set up. The model uses a helper well and writes one badly (a
  child process that never imports the code under test, a leaf certificate trusted as a CA,
  HTTPS sent to a plain-HTTP listener). Commit it, so the guard sees a clean tree.
- Copy `assets/brief-template.md`. It points the model at the plan section instead of copying
  it: pass the section, the sources the tests import, the helpers and one test file for style
  with `--read`. `python3 <this skill>/scripts/testnames.py match <source> [...]`, run in the
  target repo's root, lists the test files named after each source, the files to extend or to
  read for style.
- Its facts list holds only what those files do not say: a missing signature, a value the plan
  leaves open, and one line for each pair of behaviours that read alike saying what separates
  them. Copy nothing the model can read.
- A module the tests import that does not exist yet: pass with `--read` a file of its
  interfaces (its exports and their types, from the plan). Without it the model asked to read
  the missing file and wrote no test.
- Grep every test file for each signature, field or input shape the task changes: the tests
  that use it change too. Briefs missed such tests in four tasks; list each one under "Existing
  tests that change".
- Give one way to do each thing, never two options: the model mixed both and argued with
  itself in comments.
- Tests that share a setup: name the function that builds it and say the later tests reuse
  it; otherwise each test built its own.
- Name each import a new test needs and each one that stays; never "drop it if unused".
  `review_stats.py` ignores imports: check them with the type checker in review.
- Name the helper for each setup step in the facts ("start the server with `<starter
  helper>`; never build its config by hand"): a general "use the helpers" does not reach them,
  and the model then builds the setup itself with invented fields.
- Name every interface field the tests use, and every constant they need to build an input or
  compute a value, with its module ("import `<CONSTANT>` from `<module>`"): the model guesses a
  missing one. A value the plan gives is asserted as the plan writes it, not through the
  constant: a test that imports the value it checks passes whatever the value is.
- Give every expected value as a number, also one that follows from a rule (for "the delay
  doubles at each refusal", write the delays each test expects, not the rule): from the rule
  alone the model got every derived value wrong, from the numbers every one right.
- When the task changes what an existing test checks, list that test under "Existing tests that
  change" with the change, or "delete". A test that must stay as it is goes in the facts
  ("`<test name>` stays as it is"), not under that heading: the runner reports a test named
  there and left unchanged as "briefed change not made". Without either, the model changes the
  existing assertion itself. The runner and `review_stats.py` read the list.
- For a refusal whose input has several parts, give the accepted case as code in that test's
  own fact line: the base value and the one part changed. Described in words, the model changed
  two parts at once; listed among general facts, the model skipped it.
- One brief per run: a split task gets one brief per run, each naming only that run's `--write`
  files in backticks on its "You may edit ONLY these files:" line. The runner compares that line
  with `--write` and refuses the run (exit 2) when they differ; a file named outside `--write`
  would fail the run at the guard after the whole model run.
- Waits: a test that waits for an event only the new code sends also stops waiting on what the
  old code sends (its answer, its error), then asserts; otherwise it hangs in RED until the
  timeout instead of failing. Name the event that ends the operation (the server's answer, not
  a log file that grows before the operation ends): an assertion after a middle step ran too
  early. The template has both rules; name the events in the facts.
- An existing-test change made the same way in many tests (a rename): one pattern line,
  "- all tests: `<old>` -> `<new>`", under "Existing tests that change". The runner reports a
  test changed only by those replacements as briefed; listed by description, every one was a
  finding.
- An order a helper needs (call it before the server starts) goes in the facts, not only in the
  helper's doc comment: the model does not follow an order it only finds there.
- Every fact in the brief is checked: a mechanism you prescribe, you have run. A wrong fact
  costs a rewrite (a blocking call for a child process that calls back a server running in the
  test's own process: the server never answers).
- Give the unit of each constant the tests compute with: the model has read a milliseconds
  constant divided by 1000 as days.
- Never ask the model to run the type checker or the linter: a RED test makes them fail, and the
  model then "fixes" the source.

## Step 4: Run inside the guard

When this session's context is large, run Steps 4 and 5 in one subagent, so the main session
pays two turns, not ten. Its prompt holds this file's path, the brief path, the command, and the
instruction to return the run report of Step 5 and nothing else. Show that report to the user as
it is.

```bash
# ds4
bash scripts/run_aider_tests.sh --backend openai --ds4-dir <ds4 checkout> \
  --model qwen3.8-flash-next-nothink --num-ctx 131072 --brief <brief.md> \
  --write <test file> [--write ...] --read <path> [--read ...] \
  --fix-cmd '<formatter and lint --fix on the test files>' \
  --test-cmd '<command that runs only those tests>' --test-dir <dir> [--out <dir>]
# --test-dir: the folder both commands run in (their cwd), not the tests' folder
# Ollama: the same with --model qwen3.8-27b-nothink-120k --num-ctx 122880 --think false
```

Build the command from this step and Step 2 each time, never from a past run's command: the
backend may differ. Leave `--out` out unless the user names a folder: the default is a new
folder under `~/.local/state/local-test-writer/runs/`, which survives a reboot and keeps a copy
of the brief. Keep the brief, the plan, every `--read` file and any probe files there or in the
repo's ignored files, not in a temp dir. Take `OUT` from the runner's own `out:` line, never
from the newest folder under `runs/`: that read the previous run's report once.

Lint rules whose errors RED expects and GREEN removes (a rule that fires only because the
function under test still has its old signature, such as `no-confusing-void-expression` while it
returns void): pass them as `--red-lint-ok '<rule>,<rule>'`, so they do not count as errors left
after `--fix-cmd`.

It runs aider once with no commits and no shell commands; runs `--fix-cmd`; undoes every change
outside `--write`; scans the added lines for placeholders and for reasoning left in comments;
runs the test command; writes `report.md`. A `--write` file with uncommitted changes is kept
as it was in `OUT/before/`, and `tests.diff` is measured from it.

`--agent pi [--max-turns 40]` runs pi instead of aider, with the same guard, checks and report.

Which agent, by what the run needs:
- aider (the default): the files the model needs are known and given with `--write` and
  `--read`, and the result is edits. One turn, one reply of SEARCH/REPLACE blocks, no repo
  map, the fewest tokens. On the measured test runs its tests needed as few review changes as
  pi's or fewer, except one run where it dropped the whole reply (`lessons.md`). Its
  failures: a reply whose edits it drops, a SEARCH block that does not match.
- pi: the model has to find its own context (callers, the tests that cover a function, the
  conventions of nearby files), or aider dropped the reply of this brief before. pi reads,
  greps and lists files in a loop and edits with tool calls, so no edit is lost; it costs more
  turns and reads more tokens, so it needs `--max-turns`. Time is mixed: slower on small runs,
  faster on two large ones. On the measured runs it matched aider on PHP test edits and needed
  more review changes on large multi-file TypeScript ones.
- A run whose output is not edits, such as a code review: pi, not this runner. Run pi directly
  with read-only tools (`--tools read,grep,find,ls`) and the diff or the files in the prompt;
  aider's edit format brings nothing there, and `run_aider_tests.sh --agent pi` gives pi edit
  and write. Not measured yet.
- When a choice is not clear from the above, use aider and record the run.

With `--agent pi`, pi gets the tools read, grep, find, ls, edit and write (no shell), and the brief and the `--write` and
`--read` files attached. `scripts/pi_guard.ts` refuses an edit outside `--write` before it
happens and ends the run at the first tool call after `--max-turns` turns (up to N+1 requests);
`scripts/pi_run.py` writes `run.log` (the reply and one line per tool call), `events.jsonl`,
`pi-stderr.txt` and `pi-summary.txt` (its own errors go to `pi-run.txt`). `--think` is refused
with pi. With Ollama, pi cannot pin the window per request: the runner refuses a model whose
own `num_ctx` is not `--num-ctx` (use a variant from `make_ctx_variant.sh`). The report adds a
finding for the turn limit, for a reply that ended in an error or ran out of room, and for an
edit outside `--write` that pi_guard refused (the same intent fails an aider run), and a Note
for other failed tool calls.

A run always goes to its end. Never stop, kill or restart it, whatever the log shows: no
timeout by default (`--timeout` only when the user asks for one), and no early end because the
reply looks wrong. The runner stops one itself when the reply loops (the same block of 50 lines
or more three times in a row, each copy right after the one before), with the finding "reply
loop": such a reply never ends and gives no edit. Copies with other text between them, such as
a draft and its final version, are no loop.
With a `*reasoner*` alias the runner sends Qwen's thinking sampling (temperature 0.6, top_p
0.95, top_k 20, min_p 0); aider alone sends temperature 0, and a greedy thinking run looped
until the window was full. Everything the runner finds goes under "Findings" in `report.md`, and
expected facts (a `--write` file dirty before the run, one not named like a test file, a SEARCH
block fixed on aider's retry) under "Notes", which `review_stats.py` does not count; it exits 0;
it exits 2 only when no run can start (bad arguments, the model not in Ollama or not served by
the server). Any other exit code is a bug of the runner: `report.md` says `RUNNER ERROR`
with the line that failed; report that to the user, with no review.

One failure is fatal and fails fast: an edit outside the `--write` files, by the model or by
`--fix-cmd`. A watcher stops aider within seconds, the repo goes back exactly as it was before
the run (the `--write` files too, and a file that already had uncommitted changes goes back to
the copy the runner took at the start, in `OUT/dirty-before/`), `report.md` starts with
`FAILED` and lists the paths, and the runner exits 3. Do not fix, reuse or rerun anything from
a failed run: report it to the user with the failure form below; the next step is the user's
call.

Do not edit the repo while a run is going, not even a file of yours outside the tests (the plan,
a helper): the watcher cannot tell your edit from the model's and fails the run. Note the edit
and make it after the report.

When you start a run or hand it to the subagent, show the follow block of "Start" again. The
runner prints the run's own folder (`out:` and `log:` lines) as it starts; they go in the run
report.

Findings never block the next step: you fix every one of them in Step 5, then report it with
its fix. Never rerun the model on your own; a rerun is the user's call.

## Step 5: Review before the tests count

Read `run.log` and `chat.md` raw (the Read tool, or python writing to a file you then Read),
never through a shell wrapper that compresses tool output (rtk, headroom): it shows a log with
folded or repeated lines that look garbled, and a supervisor rewrote by hand tests that were
whole in `run.log`.

Read `tests.diff` and `test-output.txt`:
- every test the plan names exists, with the plan's values and every assertion the plan lists
  for it (the model has left half of a test's checks out, twice);
- each one fails for the stated reason: a missing module, export or behaviour, not a syntax error,
  a wrong import path or a test that hangs; a test that passes today needs a reason in the
  report (a check that something is absent, a behaviour that already holds);
- each one would fail if the code were wrong: an ordering test that ordering cannot break, a lock
  test that never waits, a child process that never runs the code under test, an assertion
  weaker than the plan, a failure swallowed (the language section lists the usual forms);
- each test of a refusal has its accepted case too (the same call or request with the one
  input changed is accepted): a refusal alone passes on any broken path that refuses too;
- each test changes one input against its accepted case: two wrong inputs at once cannot tell
  which check refused;
- every fact of the brief is used in the test it names;
- the existing tests are untouched and still pass.

Fix small defects yourself (a moved line, a missing await, a regex flag) and note them. A test
that needs rewriting is rewritten by you and counted; if more than one does, say so: the run
failed for this kind of test.

To see why each test fails, not only the first missing import: run the tests with a test
runner config kept outside the repo (in `OUT/`) that maps the missing module to a stub that
throws (the language section names the script or the recipe). Each test must then fail on its
own missing piece.

When a version of the code already exists outside the repo (a scratch or a reference
implementation), run the model's tests against it now, with the same config outside the repo,
before any code goes into the repo. A test that fails there is a wrong fact in the brief or a
model error: fix it before implementing. Checking the mechanisms is not enough: run the exact
steps of each test. There every test passes, so also make each one fail on a mutation of the
line it covers (a mutated copy of the source, outside the repo): a test that still passes
checks nothing.

Fix every runner finding, whatever the model left (none of them fails the run):
- a reply loop: the run wrote no test; report it, and a rerun is the user's call (Step 4);
- aider failed, stopped by `--timeout`, or no test added: write yourself every test the plan
  names that is missing (they count as added in review);
- the prompt is longer than the window: the model saw nothing (ds4) or a prompt cut at its start
  (Ollama). Write the tests yourself as above, and say in the report how much to cut (fewer
  `--read` files, a plan section instead of the plan) before the user's next run;
- the reply hit the token limit: no edit was applied, whatever `chat.md` shows. Write the tests
  yourself (the reply in `chat.md` can be a start, but review it as your own), and say in the
  report how much room the next run needs;
- SEARCH blocks without their `>>>>>>> REPLACE`: take each file's text from the reply in
  `run.log` (after `=======`, up to the closing fence) in place of what aider wrote, then review
  it like the others. Seen with a brief that had no facts, so check the brief kept its facts;
- aider applied none of the reply's edit blocks, for any cause (a second turn after it added a
  file the reply named; the runner's `aider_entry.py` declines those, so this is the fallback):
  the runner applied them from `run.log` (`applied-blocks.txt`, `scripts/apply_blocks.py`).
  Review them like the others; write yourself any block it could not apply;
- aider asked again for SEARCH blocks that did not match and the retry turn sent no edit block
  (the model said what it would fix and stopped): the runner applied the reply's blocks from
  `run.log` the same way, leaving the ones aider applied. Seen when the model broke off a block
  ("Wait, I need to append...") and wrote it again in full: the full one is the edit;
- a test you would write yourself whose complete block is in `run.log`: apply it with
  `apply_blocks.py`, not by hand, and in both places, so `review_stats.py` counts it as the
  model's (kept), not as added in review: from the repo root
  `python3 <skill>/scripts/apply_blocks.py <OUT>/run.log <file>`, then the same from `<OUT>/model`
  with `../run.log`. Say so in the report;
- a SEARCH block still did not match after aider's last retry: its edit is missing; write it
  yourself;
- an invisible character written as it is in an added line (`invisible-chars.txt`): write it
  as an escape (`\u3164`), so the reader sees it;
- a test file does not parse: repair it, then review its tests like the others;
- a placeholder: replace it with the real test the plan names;
- reasoning left in comments: delete it, and keep one copy of a test written twice;
- an existing test changed or removed that the brief's "Existing tests that change" does not
  name: put it back as it was. A "briefed change not made": make it. The changes the brief
  named are listed in the report apart; check that each is the one the brief gives;
- a `--write` file had uncommitted changes (a Note, not a finding): check that `tests.diff`
  holds only the model's lines and that the user's lines are still there;
- a `--write` file not named like a test file (a Note): the guard let the model edit it, so read
  its diff as production code; when it is a source file, keep only the changes the brief asked
  for.

Then measure the review against the model's version, which the runner keeps in `OUT/model/`:

```bash
python3 scripts/review_stats.py --run <OUT>     # from the repo root: every file in OUT/model/
# or, file by file:
python3 scripts/review_stats.py --report <OUT>/report.md <OUT>/model/<test file> <test file> [...]
```

Add `--lang <profile>` when the run had one. Both forms write `review.md` next to `report.md`.

It matches tests by name (typographic quotes read as plain ones) and leaves out the tests that
were there before the run and that nobody changed (`OUT/before/`). Each test is kept
(unchanged), fixed (at least half as the model wrote it, or an existing test put back),
rewritten, removed (a new test the review took out), deleted (an existing test the model
deleted and you left deleted: since you put back every deletion the brief did not ask for, it
counts as asked, not as an error), or added in review. It prints the share of the final test
lines the review changed and the run's status, the label your report starts with. It writes
the same output to `<OUT>/review.md`: read that file when the shell compresses command output.
- `DONE WITH WARNING`: serious errors fixed: a test rewritten, removed, or written by you (aider
  failed, timed out or left tests out);
- `DONE WITH NOTICE`: small errors fixed only: small fixes, runner findings fixed;
- `DONE`: nothing to fix;
- `FAIL`: an edit outside the `--write` files (runner exit 3); no review, no status from the
  script.
Use the script's status as it prints it; never pick a milder one.

The run report, in this form (the subagent returns exactly this):

```
Status: <DONE | DONE WITH NOTICE | DONE WITH WARNING> (<the reason review_stats.py prints>)
## Local test run: <task>
Follow: lmw-log | log: <OUT>/run.log
Model <name> on <Ollama | the server>, thinking <off|level, or the alias that sets it>, <seconds> s, tokens <sent> sent / <received> received
Runner findings: <none, or each line of report.md's Findings, each with how you fixed it>
Tests from the model: <N>; kept <K>, fixed <F>, rewritten <R>, removed <D>; added in review <A>
Changed in review: <X>% of the final test lines
Good: <one line per kind of test the model got right>
Wrong: <one line per defect: test name, what was wrong, the fix>
Rewritten: <one line per rewritten or removed test: name, why>
Fail for the right reason: <yes, or the tests that do not>
```

The numbers come from `report.md` and `review_stats.py`, not from estimates.

A failed run (exit 3), in this form instead:

```
Status: FAIL (edit outside the allowed files)
## Local test run: <task>
Follow: lmw-log | log: <OUT>/run.log
By: <the model | --fix-cmd>, after <seconds> s; paths: <each path report.md lists>
What it changed: <one line per path, from OUT/violations/>
Repo: back as it was before the run (git status clean of the run's changes)
```

## Step 6: Record the run

Append a dated entry to `references/findings.local.md` (create it when missing): the run
report's numbers, the brief and test sizes, and what the rewrites had in common. When the run
teaches something that is not yet a rule in this file, the brief template or `languages.md`,
add one line to `references/lessons.md` too, ending with the entry's date
("(findings <date>)"). The lesson line stays generic: names from the project belong in the
run log only.
