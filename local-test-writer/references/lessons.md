# Lessons

The distilled findings. `findings.local.md` (local, not in git) is the run log: append to it,
grep it, never read it whole.

## Models and backends

| Model | Backend | Speed | Verdict |
|---|---|---|---|
| Qwen3.8-Flash-Next Q2, `-nothink` | ds4 | 24 tok/s, 2.5x the 27B | default, tests level or better |
| Flash-Next `-reasoner` | ds4 | 8x slower | tests no better |
| qwen3.8:27b-q8_0, thinking off | Ollama | 9.6 tok/s | fallback |
| qwen3.6:27b-q8_0 | Ollama | thinking on 1289 s, off 363 s | same tests |
| qwen3.6:35b-a3b | Ollama | 275-362 s | 0 of 19 async tests, loose brief |
| qwen3-coder 30B Q4 | Ollama | 156 s | 2 of 6 usable |
| DeepSeek-V4-Flash Q2 | ds4 | | worse than the 27B, a repetition loop |

(findings 2026-11-01, 2026-11-02, 2026-11-04)

## aider vs pi

Review change, aider vs pi: PHP 0% vs 0% (once 0% vs 20%, style); TypeScript 2% vs 4%, 28% vs 59% (31% at 60 turns). pi won only where aider dropped its reply (66% vs 46%). (findings 2026-11-07) pi on PHP later: 0 to 2%, but 716 s against aider's 130-200 s; a 4-file run spent 36 of 41 turns reading given files. (findings 2026-11-10)

## Lessons not yet rules

None now: the earlier ones are rules in SKILL.md, the brief template and languages.md
(2026-11-13). Step 6 adds a line here for each new one, with its findings date.

## Open problems

- A reply with no edits: prose ending "Let me craft the edits", or "add these files to the chat". Seen with 56k-68k token prompts, 4 `--write` files, sources the plan says to change in `--read`. Try fewer files. (findings 2026-11-11, 2026-11-12)
- A brief's `\uXXXX` comes back as the raw character; typographic quotes get normalised. The runner flags invisible characters only. (findings 2026-11-12)
- No stub run when the helpers import the new module. (findings 2026-11-10)
- Jest: a RED rejection with no `catch` crashes the worker; run the others with `-t`. (findings 2026-11-12)
