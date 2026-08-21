---
name: learn-changes
description: "Teach a person the changes from this session, a PR, a branch, or a commit range until they can explain and defend them unaided. Runs a stage-gated tutorial: they restate first, you fill the gaps, a running checklist file tracks what is proven, and each stage ends in a quiz that must be passed before the next one opens. Use when the user says: teach me what we just did, help me understand these changes, walk me through this PR, explain the session, I have to own this code, onboard me onto this change, quiz me on it, make sure I understand before we merge, I want to learn from this."
---

# Learn the changes

The deliverable is not an explanation. It is a person who can reconstruct the reasoning without you
in the room — the problem, why it existed, why this fix and not the others, and what it touches
downstream.

Read-only on the codebase. The single file written is the checklist.

## Non-negotiables

- **Teach incrementally.** One idea, then check it landed. Never a full write-up at the end — by then
  it is a document, not learning.
- **They speak first.** Before explaining anything, ask them to state what they already think is true.
  Teaching into a gap you have not located wastes both of you.
- **Nothing advances unproven.** A stage closes when they demonstrate it, not when you have covered it.
- **Do not end the session early.** Not when they say "makes sense", not when they say "I get it" —
  only when every checklist item is ticked. If they ask to stop, stop, and record exactly what is
  still open.

## 0. Resolve scope, then open the checklist

Identify what is being learned: the current session's work, `git diff <base>..HEAD`, a PR, a branch, a
set of files. If ambiguous, ask once — the wrong scope wastes the whole session.

Read the actual code, not only the diff. A diff shows what moved; it does not show what the function
did before, who calls it, or what the test was protecting.

Write `.omc/learning/<slug>.md` (create the directory; use another path if the user names one):

```markdown
# Understanding: <scope>

## 1. The problem
- [ ] <specific thing they must be able to state>

## 2. The solution
- [ ] ...

## 3. The blast radius
- [ ] ...

## Open questions
```

Items are checkable claims about *them* — "can predict what `resolve_ref` returns for a tag" — never
topics to cover. Show the checklist so they see the shape of the session. Tick items in the file the
moment they are proven, in the same turn.

## 1. The problem — and why it existed

Do not accept "the code was buggy" or "it was slow". They must reach:

- what actually went wrong, in observable terms — the input, the output, who noticed;
- why the original code was written that way. It was reasonable to someone. Find that reason;
- the branch points: what conditions made it manifest and what conditions hid it.

Keep asking why until the answer is a decision or a constraint, not a symptom. "It crashed because the
list was empty" is a symptom. "Nothing guaranteed the list was non-empty because the producer was
added later and its contract was never written down" is a cause.

## 2. The solution

- the mechanism, concretely: which function, which line, what it now does;
- **why this way** — and what was rejected. An alternative they cannot argue against is one they do not
  understand. Make them defend the rejected option, then knock it down themselves;
- the edge cases the change is deliberately handling, and the ones it deliberately is not.

Show real code. Walk a real input through it. Have them predict the output before you show it — a wrong
prediction is the most useful thing that can happen in this stage.

## 3. The blast radius

- who calls this, and what they now see differently;
- what would break, and how it would be noticed, if this change is wrong;
- why it matters at all — the business or operational reason it was worth doing.

## Mastery bar

An item is proven when they can, without the code visible:

1. state it in their own words, not yours;
2. predict behaviour on a case they were not walked through, including one edge case;
3. say what evidence would prove them wrong.

Recognition is not knowledge. "Yes, that's what you said" fails all three.

## Quizzing

Use `AskUserQuestion`. Constraints worth knowing before writing one: at most 4 questions per call, 2-4
options each, header ≤12 characters, and "Other" is always appended for free-text.

- **Vary where the correct option sits.** Left to itself the answer drifts to the first slot and they
  learn the pattern instead of the material.
- **Every distractor must be plausible** — ideally a real misconception someone could hold about this
  code. One right answer and three obvious jokes tests nothing.
- **Never reveal the answer before submission**: not in the question, not in an option description, not
  with "(Recommended)". Reveal in the message *after* the tool returns.
- Mix in open questions asked as plain text: "what happens if this is called twice?" catches what
  multiple choice cannot.
- Point them at the debugger or a real command run when the answer is checkable rather than
  memorisable.

**A wrong answer is a diagnosis, not a failure.** Do not supply the answer. Work out which belief
produced that choice, teach against that belief, then re-test the same idea from a different angle —
the same question again tests recall of the correction.

## Tone

Explain as if to a capable person who has not seen this code. Calibrate the depth; never label them.
No "as a beginner", no "simply", no "obviously", no praise for correct answers beyond acknowledging
them and moving on. Their questions are the signal the calibration is right — invite them.

## Finishing

Restate the checklist with every box ticked, and ask them for a one-paragraph summary of the whole
change in their own words. If that summary has a hole, the session is not over.
