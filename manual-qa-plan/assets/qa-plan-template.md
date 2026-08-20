# Manual test plan — <release or change-set name>

**Covers:** `<BASE>` → `<HEAD>` (<n> commits, <n> changed files)
**Prepared:** <date>
**Environment to test on:** <environment and URL>

## How to use this document

Work through the cases in order; they are sorted by priority. Each case states what to set up first,
what to do, and what you should see. Record the case ID and the outcome. If what you see differs from
the expected result in any way, stop on that case and report it with the ID — a partial match is a failure.

Where a case shows a **previous / new** table, the behaviour deliberately changed: the old result is
no longer correct. Where a case says **regression check**, nothing should have changed and seeing the
old behaviour is the pass.

## Summary of what changed

| # | Area | What changed, in one sentence | Cases |
|---|---|---|---|
| 1 | <area> | <plain-words summary> | T-1, T-2 |

## Test cases

<!-- One block per case, following the anatomy in references/writing-test-cases.md. Highest priority first. -->

### T-1 · <title>

**Area:** <area>
**Priority:** P1
**Why it needs checking:** <one sentence>

**Before you start**
- <precondition>

**Steps**
1. <action>

**Expected result**
- <observable outcome>

**If this fails you will see**
- <concrete wrong outcome>

| | Previous behaviour | New expected behaviour |
|---|---|---|
| <situation> | <old> | <new> |

## Changed but not manually testable

These changed in this release and were reviewed. None of them can alter what a user sees, for the reason given.

| File or area | Reason it needs no manual check |
|---|---|
| <path> | <specific reason> |

## Open questions for the developer

These could not be turned into a test that someone can run unaided. Each needs an answer before this area can be signed off.

| # | Question | Why it blocks testing |
|---|---|---|
| Q-1 | <question> | <what cannot be reached or confirmed without it> |

## Appendix — traceability

For reference when reporting a problem. Not needed to run the tests.

| Case | Changed files behind it |
|---|---|
| T-1 | `<path>` |
