# Findings

What was measured, and why the skill is built the way it is. Add a dated entry for every run
that teaches something; keep the numbers.

## 2026-11-01: qwen3-coder 30B (Q4_K_M, 120k context) through opencode: failed

Task: six failing tests for a TypeScript/vitest project (database lock, migrations, file
modes, one transaction, one lint rule), "tests only".

What it did in about four minutes, before it was stopped:
- edited two source files (added the constant the test was about; a stub that throws);
- created a new source file with half of the function under test;
- wrote five of six tests as `throw new Error('Test not implemented yet')`; only the lint test
  was real.

Checked and ruled out:
- chat format: the variant kept `RENDERER qwen3-coder` and `PARSER qwen3-coder`;
- context: prompts peaked near 29k of 122,880 tokens, `truncated = 0` in the Ollama log;
- sampling: Qwen's recommended values (temperature 0.7, top_p 0.8, top_k 20, repeat 1.05).

Causes found:
- opencode gives any model it has no dedicated prompt for (Qwen included) its generic system
  prompt, which says "VERY IMPORTANT: When you have completed a task, you MUST run the lint
  and typecheck commands ... to ensure your code is correct." A failing-test task needs the
  type check to fail; a small model obeys the louder rule and "fixes" the source.
- the brief asked it to run the type checker and report errors, which reinforced that rule;
- "tests only" was an instruction, not a barrier: `edit: allow` let it write anywhere.
- it was stopped mid-run; its last message said it was about to replace the placeholders.

Hence this skill: aider, which edits only the files passed with `--file`; no type-check or
lint step in the brief; a guard script that undoes anything outside `--write`; a placeholder
scan; a template that says a missing-function failure is the correct result.

Memory on a 64 GB Mac (Chrome, a terminal, Claude Code, one editor): the 120k variant loaded
at 31 GB, the system peaked at 53.9 GiB, swap flat.

## Harness notes
- aider 0.86 on Python 3.13 crashes at start (`No module named 'audioop'`); install it on
  3.12: `uv tool install --force --python 3.12 aider-chat`.
- Ollama.app reads its environment only at start (`launchctl setenv`, then quit and reopen).
  The KV cache multiplies by `OLLAMA_NUM_PARALLEL`; keep it at 1 for a big window.
- Ollama.app's own context setting exports `OLLAMA_CONTEXT_LENGTH` for every model without a
  `num_ctx`; the variant script pins `num_ctx` so the agent's model is unaffected.
- With a server-wide `OLLAMA_MAX_LOADED_MODELS` above 1, a second large model loaded by
  another process stays resident next to the agent's; check `ollama ps` before a run.

## 2026-11-01: the same model and task through aider (this skill): 2 of 6 usable

Run 1: aider answered in the system locale's language (Italian), listed the six tests,
announced "I will now implement them" and exited: `--message-file` gives one reply only. Fixed
with `--chat-language English` (now the default) and a brief line "answer with the edits now;
there is no second turn"; exit code 6 added for a run that adds no test.

Run 2: 156 s, 10k tokens sent, 6.7k received; the guard found no edit outside the three test
files (the barrier held where opencode's did not). Review, test by test:
- `createWithRoom writes both or neither`, `Math.random is refused`: correct, exact values,
  fail for the right reason. Usable as written.
- `a write waits for another process's lock`: the child commits at once, so nothing ever
  waits; the lock is not tested. Rewrite.
- `two processes opening a new file migrate it once`: imports `./src/db/open.ts` relative to
  the working folder, ignores the exit codes, hard-codes version 1; passes today. Rewrite.
- `openAppDb makes the folder and file private`: destructures a Promise, so it always reaches
  `expect(true).toBe(false)`; no mode assertion. Placeholder (the scan flagged it).
- `no backup file is made`: same Promise mistake around `node:fs`, then asserts the opposite of
  the brief (requires the WAL files). Placeholder (flagged).

Verdict: discarded (more than one test to rewrite). The model handles a simple synchronous test
with the setup spelled out; it fails on child processes, timing and async imports.

## 2026-11-01: qwen3.6 35B-A3B (Q8_0, 120k context, thinking on) through aider: 4 of 6 as written

Same brief and files as the qwen3-coder run. Variant `qwen3.6-coding-120k`: Qwen's coding
values for thinking mode (temperature 0.6, top_p 0.95, top_k 20, min_p 0, presence_penalty 0;
the base ships presence_penalty 1.5). Hybrid model (KV cache every fourth layer): 20 KiB per
token, so 120k context costs about 2.3 GiB; loaded at 39 GB, 100% GPU, swap flat.

275 s, 10k tokens sent, 13k received (thinking included); guard clean, no placeholders; the
RED was the expected one (missing `app-db.ts` module, missing `createWithRoom`, missing lint
rule). Review, test by test:
- `two processes opening a new file migrate it once`, `openAppDb makes the folder and file
  private`, `no backup file is made`, `Math.random is refused`: as the brief asks. Usable.
- `createWithRoom writes both or neither`: right behaviour, stronger than asked
  (`toThrow('no rooms')`), but the trigger quotes the message with double quotes, which
  SQLite reads as a string only through its legacy double-quoted-string fallback. One-word fix.
- `a write waits for another process's lock`: the wait is real this time (the child holds
  `BEGIN IMMEDIATE` when the insert runs), but it reads `PRAGMA busy_timeout` as
  `.busy_timeout`; SQLite names the column `timeout`, so the test could never pass. It also
  leaves the first `openDb` handle open. Two-line fix.

Verdict: usable after two small fixes, none a rewrite. A clear step up from qwen3-coder 30B
(2 of 6) on child processes and async, at about twice the time. Diff kept as evidence, files
reverted (the trial was not the task's execution).

Harness note: the guard hashes every untracked file before and after the run (3157 in this
repo, about a minute each way); a repo with large untracked files pays for it.
