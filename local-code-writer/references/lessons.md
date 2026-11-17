# Lessons

The measured lessons, short. `findings.local.md` (local, not in git) holds the runs behind
them; grep it by date.

## Code runs of the reasoner (ds4 `qwen3.8-flash-next-reasoner`, window 131072, aider)

| Plan given to the model | Files | Time | Received | Result |
|---|---|---|---|---|
| signatures and call order per file | 2 | 352 s | 6.4k | 6 small fixes |
| same, 4 files new | 6 | 2344 s | 52k | 8 small fixes |
| same | 2 | 1827 s | 39k | 13 small fixes; one logic fix, a race in the plan |
| narrow review-fix brief | 3 | 446 s | 6.1k | exactly the brief, green first time |
| narrow review-fix brief | 3 | 614 s | 10k | exactly the brief; one old test needed a change |
| refactor plus a new export, per file | 6 | 1199 s | 20k | 121 tests green first time |
| loose plan, stateful I/O module | 4 | 2646 s | 58k | green, but casts and type errors: rewritten |
| no per-file detail (PHP) | 1 | 1704 s | 38k | about 4k of code: not worth it |
| bodies already written as code | 9 | 3544 s | over the window | thinking looped; nothing applied |
| signatures, SQL and call order per file, greedy | 2 | 4080 s | 96k, stopped | thinking looped; nothing applied |
| the same brief, sampling on | 2 | 517 s | 9.4k | green first run: tsc, lint, 100% coverage, no fix |

Every row but the last ran greedy: aider sent temperature 0 until 2026-11-16, when the runner
started to send sampling. The last two rows are one brief run both ways: greedy looped for 68
minutes, sampling on was green in under 9. Measure the others again with sampling on.

## The per-file plan

The reasoner writes correct code when the brief gives, for each source file, the signatures,
the messages and the order of the calls, as code. With a loose plan it reaches green tests with
code that Claude rewrites. Run order matters: each run reads the files earlier runs wrote.

## Time

Time = received tokens / 18 per second (measured 14 to 24, prefill included). Received tokens
are about 10 times the tokens of the code: most of them are thinking.

## Lessons not yet rules

- A brief whose plan already gives every body as code, over 9 files: the thinking re-planned the
  same edits 33 times until the reply hit the window. Groups of 1 or 2 files avoid the file
  count; with bodies as code, the reasoner adds nothing (findings 2026-11-13).
- That loop, and the one of 2026-11-16 (a 224-line block 34 times, 68 minutes), ran greedy:
  aider sends temperature 0 when the model settings give no `use_temperature`, and ds4 obeys
  it. The runner's loop guard finds both in their `run.log`, and no other loop in 240 logs.
- The guard counts only copies in a row. A first version counted three copies anywhere in the
  turn, and on 2026-11-17 it stopped a healthy run with sampling on in the middle of its
  answer: the thinking drafted the code, reviewed it, drafted it again, and the answer wrote it
  a third time. Copies far apart are a thinking reply's normal shape; a greedy loop puts each
  copy right after the one before (34 times on 2026-11-16).
  Still open: does a brief with the call order spelled out cost thinking that one with
  signatures, messages and SQL only does not? Measure both at the same sampling
  (findings 2026-11-16).
