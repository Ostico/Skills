---
name: explain-plainly
description: "Unpack something already on the table that was stated too briefly or too densely — a two-word finding, a jargon phrase, a review comment, an error label, a line of a plan, a term used without explanation. Produces a clear plain-words description plus the real impact, without padding. Use when the user says: explain this in plain words, plain English, ELI5, what do you mean by that, you explained that in two words, unclear, too complex, be clearer, expand on that, what does that actually mean, what's the real impact, does this actually matter."
---

# Explain Plainly

The subject is already named — a phrase, finding, or sentence someone (often you) compressed too far. Job: expand it into words that stand on their own, then say whether it actually matters.

## Steps

1. **Quote the exact phrase** being unpacked, so there is no doubt what is being explained.
2. **Read the thing it refers to** — the file and line, the error output, the config value. Never explain from the phrase alone; the phrase is what was unclear.
3. **Unpack every compressed term.** One plain sentence per jargon token: what it is *and what it does here*. Not the textbook definition.
4. **Show what actually happens** with concrete values, real names from the code, a real sequence. Abstract restatement is the failure mode.
5. **Size the impact honestly.** Who or what is affected, when, how badly. Give the base numbers, not just a percentage. "Nothing breaks in practice, because …" is a valid and common answer — say it when true rather than inflating.
6. **Say what to do**, or say that nothing needs doing.

## Output

```
**Plain version** — 1-3 sentences, zero jargon.
**What actually happens** — the concrete walk-through or example.
**Why it matters** — real impact, sized; or why it doesn't.
**What to do** — one line, or "nothing".
```

Drop any section that would be empty. Under ~200 words unless the mechanism genuinely needs more.

## Rules

- **Replace jargon, don't relabel it.** If the plain version still needs a glossary, it failed.
- **Concrete beats general.** Real identifiers, real numbers, real inputs from this codebase.
- **No hedging fog.** If something is a guess, mark it once — "guess:" — and stay direct.
- **Keep negations and units exact.** Never lose a `not`, `only`, or `except` while shortening.
- **No preamble, no restating the question, no praise, no closing offer to help.**
- Short is the constraint on wording, not on substance: cut adjectives, never the impact or the caveat.
- **Read-only.** Explaining is not fixing. Do not edit, create, or delete anything in the repository, and run no command that changes the working tree — step 6 says what to do, it does not do it.
