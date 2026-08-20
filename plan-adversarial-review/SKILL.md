---
name: plan-adversarial-review
description: Adversarially stress-test a plan, spec, or design before implementation by fanning out three independent refuters (correctness, security, feasibility) and synthesizing their findings into a single GO / NO-GO verdict. Use when the user says "review plan", "adversarial check", "red team this", "poke holes", "what am I missing", or before committing to any non-trivial plan or architecture decision.
triggers:
  - review plan
  - adversarial check
  - red team
  - poke holes
  - what am I missing
argument-hint: "<plan text, file path, or reference to the plan in context>"
---

# Plan Adversarial Review

## Purpose

Catch fatal flaws in a plan BEFORE implementation. Three independent reviewers each attack the plan from one angle, blind to each other. A synthesis pass dedupes, ranks by severity, and issues a single verdict. Independence is the point — one reviewer rationalizes; three from different lenses corner the gaps.

## When to activate

- User asks to review/critique/red-team a plan, spec, design doc, or proposed change.
- Before starting any 5+ step or multi-module implementation.
- After `/plan` or a planning skill produces a work plan and you want a gate before execution.

## Inputs

The plan to review. Resolve it from, in order:
1. Explicit text or file path in the argument.
2. A plan file referenced in the conversation (`.omc/plans/*.md`, a pasted plan, prior message).
3. If none found, ask the user for the plan — do not invent one.

Read the plan in full first. If it references code, read the real files — reviewers must verify claims against the actual codebase, not the plan's description of it.

## Workflow

Run the three refuters in parallel, then synthesize. Use the Workflow tool so they execute concurrently and independently. Each refuter gets ONLY its lens and is told to try to break the plan.

```javascript
export const meta = {
  name: 'plan-adversarial-review',
  description: 'Three blind refuters attack a plan, one synthesis verdict',
  phases: [{ title: 'Refute' }, { title: 'Synthesize' }],
}

const PLAN = args.plan            // pass the full plan text/context in via args
const CONTEXT = args.context || ''  // relevant file paths or code excerpts

// Shared hostility clamp prepended to every lens. Defeats the model's default
// politeness: a prior of guilt, "looks fine = FAILED", no suppression of low-confidence
// findings, attack-the-strongest-claim, zero praise.
const HOSTILE_FRAME = `PRIOR: this plan is flawed until you prove otherwise. Your job is to find the flaw, NOT to bless the plan. A reviewer who returns "looks fine" has FAILED this review. If you found nothing, you did not look hard enough — go deeper: trace second- and third-order effects, read the actual code, attack the weakest step AND the strongest claim.

RULES:
- Zero praise. No "overall solid." Lead with the worst finding.
- Surface EVERY concern, even low-confidence ones — label them, never suppress them. A missed flaw is the only failure that counts; a false alarm is cheap.
- Attack the plan's STRONGEST claim, not just soft spots. Find the assumption that, if wrong, collapses everything.
- Verify against the REAL files. "The plan says X" is NOT evidence that X is true — open the file and check.
- Rank severity by blast radius × likelihood. critical = plan ships and breaks prod or fails its goal; significant = real harm/rework; minor = worth noting.
- For each finding: severity, evidence (file:line or direct quote), consequence, fix, confidence (fact/inference/speculation).
- List attacks you actually ran but the plan SURVIVED under triedButSound — only real attempts, with what you checked. Empty triedButSound means you did not try.
- READ-ONLY. You are reviewing a plan, not executing it: do not edit, create, or delete anything in the repository, and run no command that changes the working tree. Scratch files under a temp directory are fine. Report the fix; never apply it.`

const LENSES = [
  {
    key: 'correctness',
    prompt: `You are a hostile CORRECTNESS reviewer in an adversarial red-team. ${HOSTILE_FRAME}\n\nYOUR LENS — prove this plan does NOT achieve its stated goal. Hunt for: wrong logic, hidden assumptions never checked, missing edge/error/null/concurrent/partial-failure cases, wrong step ordering, unstated prerequisites, untestable or absent success criteria.\n\nPLAN:\n${PLAN}\n\nCONTEXT:\n${CONTEXT}`,
  },
  {
    key: 'security',
    prompt: `You are a hostile SECURITY reviewer in an adversarial red-team. ${HOSTILE_FRAME}\n\nYOUR LENS — prove this plan introduces vulnerability or data risk. Hunt for: injection, authz/authn gaps, secret/credential handling and leakage (including logs), unsafe deserialization, race conditions with security impact, trust-boundary violations, missing input validation. Map OWASP-style failure modes where relevant.\n\nPLAN:\n${PLAN}\n\nCONTEXT:\n${CONTEXT}`,
  },
  {
    key: 'feasibility',
    prompt: `You are a hostile FEASIBILITY reviewer in an adversarial red-team. ${HOSTILE_FRAME}\n\nYOUR LENS — prove this plan is harder, riskier, or more incomplete than it claims. Hunt for: silently omitted work ("etc." hiding real effort), underestimated blast radius (callers/tests/contracts/migrations/submodules that must change together), missing rollback story, partial-completion states, dependency/sequencing problems, and verification gaps (how would anyone know it actually worked?).\n\nPLAN:\n${PLAN}\n\nCONTEXT:\n${CONTEXT}`,
  },
]

// minLength guards defeat the "test"/probe-submission failure mode: a subagent that
// fires StructuredOutput with placeholder fields ("t"/"e"/"c"/"f") to test the tool
// shape gets REJECTED by validation → the harness forces a retry with real content.
// Without these, a schema-valid garbage submission terminates the agent and discards
// its real analysis. `lens` must echo the actual lens name (not "test").
const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['lens', 'findings'],
  properties: {
    lens: { type: 'string', minLength: 8, description: 'the actual lens name (correctness/security/feasibility), never "test"' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'title', 'evidence', 'consequence', 'fix', 'confidence'],
        properties: {
          severity: { type: 'string', enum: ['critical', 'significant', 'minor'] },
          title: { type: 'string', minLength: 12 },
          evidence: { type: 'string', minLength: 20, description: 'file:line or direct quote — real, not a placeholder' },
          consequence: { type: 'string', minLength: 20 },
          fix: { type: 'string', minLength: 20 },
          confidence: { type: 'string', enum: ['fact', 'inference', 'speculation'] },
        },
      },
    },
    triedButSound: { type: 'array', items: { type: 'string', minLength: 20 }, description: 'attacks attempted that the plan survived' },
  },
}

phase('Refute')
const reports = await parallel(
  LENSES.map(l => () =>
    agent(l.prompt, { label: `refute:${l.key}`, phase: 'Refute', schema: FINDINGS_SCHEMA, effort: 'xhigh' })
  )
).then(r => r.filter(Boolean))

phase('Synthesize')
const synthesis = await agent(
  `You are the synthesis judge of an adversarial red-team. Three independent reviewers attacked this plan. Do NOT soften their findings to be agreeable — your bias is toward catching the fatal flaw, not toward shipping. Dedupe overlapping findings, rank by blast radius × likelihood, and demote ONLY findings that are pure speculation with zero supporting evidence (keep low-confidence findings that have evidence). Default the verdict to NO-GO unless the plan demonstrably survives every critical attack.\n\nIssue ONE verdict: GO / GO WITH CHANGES / NO-GO.\n\nReviewer reports (JSON):\n${JSON.stringify(reports, null, 2)}\n\nPLAN:\n${PLAN}\n\nReturn: the verdict + one-line why; merged critical findings (evidence + consequence + fix); significant findings; open questions; an explicit list of what the plan OMITS entirely; and a short "verified-OK" list of attacks the reviewers actually ran that the plan survived. If the three reviewers disagree on a finding's severity, take the HIGHER severity unless you can refute it with evidence.\n\nLENS-HEALTH CHECK: before judging, inspect each report. If any lens returned zero findings AND empty triedButSound, or fields that look like placeholders, treat that lens as NON-FUNCTIONING (not as "clean") — state explicitly which dimension went unreviewed and factor the coverage gap into the verdict. A dimension that did not run is a reason to withhold GO, not to assume safety.\n\nREAD-ONLY: you are issuing a verdict, not applying fixes. Do not edit, create, or delete anything in the repository, and run no command that changes the working tree.`,
  { label: 'synthesize', phase: 'Synthesize', effort: 'xhigh' }
)

return synthesis
```

## Output to the user

Present the synthesis verdict directly. Structure:

1. **Verdict** — `GO` / `GO WITH CHANGES` / `NO-GO`, one line why.
2. **Critical findings** (block the plan) — `[🔴] title` + evidence + consequence + fix.
3. **Significant findings** (should fix) — same format.
4. **Open questions / minor** — bulleted.
5. **What's missing** — work the plan omits entirely.
6. **Verified-OK** — what reviewers tried to break and couldn't.

## Notes

- Refuters run blind to each other — do not let them see each other's output before synthesis. That independence is what catches gaps a single pass rationalizes away.
- Agent calls run at `effort: 'xhigh'` for deep reasoning; drop to `'high'` to save tokens on low-stakes plans, or raise to `'max'` for critical ones.
- The skill only critiques. It does NOT rewrite the plan or start implementing. Offer fixes, not a replacement design, unless the user asks.
- A clean `GO` is a valid result — but only after a genuine attempt to break the plan, proven by the "verified-OK" list.
- If the Workflow tool is unavailable (no multi-agent opt-in), fall back to dispatching three parallel subagents via the Agent tool with the same three lens prompts, then synthesize their reports yourself.
