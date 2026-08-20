# Writing the test cases

Contents: [Who reads this](#who-reads-this) · [Anatomy](#anatomy-of-a-test-case) ·
[Before and after](#the-before-and-after-table) · [Worked example](#worked-example) · [Rewrites](#common-rewrites)

## Who reads this

Someone who knows the product as a user and does not read the source code. They can navigate the app,
create records, and use an API client if given the exact request.

Consequences for every line written:

- **Never name code in the steps.** No class, function, file, table, or branch names in the procedure. Those belong in the appendix.
- **Never state or imply the reader's experience level.** No "simple", "obviously", "just", "basic", "even a beginner". Write plainly and completely; that is what respect looks like here.
- **Every step is an action a person performs**, in the order they perform it. No step that begins "ensure that" without saying how.
- **Expected results are observable.** Quote the exact text, number, or state shown on screen. "Works correctly" is not an expected result.
- **Say how failure looks**, not only how success looks. The reader must be able to tell the difference without asking.

## Anatomy of a test case

```
### T-<n> · <short title in plain words>

**Area:** <the product feature a user would name>
**Priority:** P1 | P2 | P3
**Why it needs checking:** <one sentence: what changed, in product terms>

**Before you start**
- <account and role needed>
- <record / project / data state needed>
- <flag, setting, or environment needed>

**Steps**
1. <action>
2. <action>

**Expected result**
- <observable outcome, exact wording where there is wording>

**If this fails you will see**
- <the concrete wrong outcome to watch for>
```

Give every case a stable ID (`T-1`, `T-2`, …) so results can be reported back by number.

## The before and after table

Include it whenever behaviour changed. Omit it for behaviour that is new (nothing to compare) — say "new behaviour, nothing to compare" instead.

| | Previous behaviour | New expected behaviour |
|---|---|---|
| <the situation> | <what used to happen> | <what happens now> |

Two rules that matter:

- Describe both sides in **product terms**, not code terms. "The score dropped to zero" — not "the counter was clamped by `GREATEST`".
- If a case exists to confirm something **did not** change, say so explicitly: *"Unchanged — this is a regression check."* Those cases are as important as the changed ones, and a reader who does not know they are regression checks will report them as "nothing happened".

## Worked example

Weak — unusable by the intended reader:

> Verify `ChunkReviewDao::passFailCountsAtomicUpdate` correctly clamps `penalty_points` when a delta is negative.

Rewritten:

> ### T-4 · Removing a quality issue lowers the score, and never past zero
>
> **Area:** Revision — quality score
> **Priority:** P1
> **Why it needs checking:** the way the score is recalculated when issues are added and removed was rewritten.
>
> **Before you start**
> - An account that can revise, and a project with at least one job open for revision
> - The job's quality score visible and currently zero issues recorded
>
> **Steps**
> 1. Open the job in revision.
> 2. Add a quality issue to any segment, choosing a category worth several penalty points.
> 3. Note the quality score shown.
> 4. Delete that same issue.
> 5. Reload the page.
>
> **Expected result**
> - After step 2 the score reflects the penalty.
> - After step 5 the score has returned to exactly the value it had before step 2.
> - At no point is a negative score displayed.
>
> **If this fails you will see**
> - A score that stays lowered after the issue is deleted, or a score that differs after reloading the page from the one shown before reloading.
>
> | | Previous behaviour | New expected behaviour |
> |---|---|---|
> | Deleting the last remaining issue | Score could be left at a stale non-zero value | Score returns to its starting value |

## Common rewrites

| Do not write | Write instead |
|---|---|
| "Check the endpoint returns 200" | "The page loads and shows the job list" — or, for an API case, give the full request and the exact response field to read |
| "Ensure the cache is invalidated" | "Reload the page. The new name appears, not the old one." |
| "Test the worker runs" | "Wait up to two minutes, then reload. The status reads *Completed*." |
| "Verify permissions" | "Sign in as a user who is not a member of this project and open the link. Expect *You are not authorised*." |
| "Should work as before" | State what "as before" looked like, in the before/after table |
