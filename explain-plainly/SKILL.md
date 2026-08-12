---
name: explain-plainly
description: "Explain something in plain words, briefly, and evaluate its REAL impact rather than its claimed impact. Use when the user asks to explain, clarify, or break down anything — code, a diff, an error, a dependency bump or CVE, release notes, an RFC or announcement, a config change, a benchmark, a contract clause — and especially when they say: explain this in plain words, plain English, ELI5, what does this actually mean, what does this actually change, does this affect us, should I care, what breaks, is this a big deal, cut the hype, real impact, don't be verbose. Also use when the user is deciding whether to act on someone else's claim of importance."
---

# Explain Plainly

Two jobs, in order: make the thing understandable, then judge what it actually changes. The second job is the one people are usually paying for and the one most explanations skip.

## Non-negotiables

- **Ground first, explain second.** Read the real artifact — the file, the diff, the changelog entry, the actual code the release notes describe. An explanation written from someone else's summary inherits their claims, including the wrong ones. If grounding needs a broad sweep, delegate it (`Agent(subagent_type="Explore", ...)`) and keep only the findings.
- **Explain the mechanism, not the label.** Test before shipping a sentence: could the reader now predict behavior in a case you did not mention? If not, the sentence only renamed the thing.
- **"No real impact" is a valid and common verdict.** State it plainly when true. Manufacturing significance to seem useful is the main failure mode of this skill.
- **Separate claimed impact from real impact.** What the author says it does is evidence, not truth. See [references/impact-rubric.md](references/impact-rubric.md) for the false-impact catalogue — check the subject against it before writing the verdict.
- **Label confidence.** `fact` (verified in the artifact), `inference` (reasoned from it), `unknown` (would need to check X). Never dress inference as fact.
- **Brevity is a constraint, not a style.** Budget below. Cutting words is not permission to cut the verdict, the caveat, or the negation.

## Workflow

1. **Fix the subject and the "who."** What exactly is being explained, and impact *on whom* — this repo, this user's deployment, their team, their users? Impact is meaningless without a target. If the target is genuinely unclear and the answer flips depending on it, ask one question; otherwise pick the most likely target and name the assumption in one clause.

2. **Read the actual thing.** Open the files, run the command, check the version diff. Note what you could not verify — that becomes `unknown`, not silence.

3. **Find the mechanism.** How does it work, one level below the name? Stop at the depth where the reader can predict behavior — deeper is verbosity.

4. **Test reachability.** Is there a real path from the target's usage to this change? Grep for the affected API, flag, config key, code path. No caller, no flag enabled, no matching version = no impact, and say so with the evidence.

5. **Ground the magnitude.** Convert every relative number into the target's absolute units: ms, requests, dollars, rows, hours of work, number of files to touch. "30% faster" on a 4 ms path is nothing. "Up to 10×" is a best case, not a typical case.

6. **Write the verdict.** Rank real effects by size × likelihood. Include what will happen if the user does nothing — that is the true baseline they are comparing against.

7. **Check the negation.** Reread and confirm no `not` / `only` / `except` / unit was lost while trimming. A compressed explanation that flips a meaning is worse than a long one.

## Output format

Use these sections, drop any that would be empty, keep the order:

```
**What it is** — 1-3 plain sentences.
**How it works** — the mechanism, only as deep as step 3 requires.
**Real impact** — ranked. Each: who/what is affected · magnitude in concrete units · [fact/inference/unknown].
**Not affected** — what sounds relevant but isn't, with the reason it isn't.
**If you do nothing** — the default outcome.
**Worth checking** — the one or two unknowns that would firm up the verdict.
```

**Budget:** total under ~250 words for an ordinary subject, under ~450 for a genuinely layered one. If it will not fit, cut explanation depth first, never the impact verdict. Bullets carry one idea each.

## Banned moves

| Move | Why it fails |
| --- | --- |
| Restating the question before answering | Pure token cost |
| "Great question", "In summary", "Let me know if…" | Fluff |
| Jargon swapped for more jargon | Not an explanation |
| Analogy in place of mechanism | Feels clear, predicts nothing. Analogy after mechanism is fine, and only if it earns its line |
| Hedging every sentence | Confidence labels exist so prose can be direct |
| Bullet soup with no verdict | The verdict is the deliverable |
| Impact stated only in the author's percentages | Ungrounded, see step 5 |
| Inflating a nothing-burger | Destroys the skill's usefulness |
| Praising the thing being explained | Not asked for |

## Reference

[references/impact-rubric.md](references/impact-rubric.md) — read before writing the **Real impact** section. Contains the false-impact catalogue (ten patterns that read as important and are not), magnitude-grounding rules, and per-subject playbooks: code/diff, error or stack trace, dependency bump or CVE, release notes/announcement/RFC, config change, benchmark output, architecture proposal, contract or policy text.
