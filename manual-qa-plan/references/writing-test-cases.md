# Writing the test cases

Contents: [Who reads this](#who-reads-this) · [Anatomy](#anatomy-of-a-test-case) ·
[Before and after](#the-before-and-after-table) · [Worked example](#worked-example) · [Rewrites](#common-rewrites)

## Who reads this

Someone who knows the product as a user and does not read the source code. They can navigate the app,
create records, and use an API client if given the exact request.

Consequences for every line written:

- **Never name code in the steps.** No class, function, file, table, or branch names in the procedure. Those belong in the appendix. Routes, URLs and screen names are not code — the reader needs those.
- **Say where the work happens before saying what to do.** The interface, an API client, a mail client, a shell, the devtools Network tab. A tester who reaches step 1 and only then discovers they need a tool has been sent back to the start.
- **Never state or imply the reader's experience level.** No "simple", "obviously", "just", "basic", "even a beginner". Write plainly and completely; that is what respect looks like here.
- **Every step is an action a person performs**, in the order they perform it. No step that begins "ensure that" without saying how.
- **Expected results are observable.** Quote the exact text, number, or state shown on screen. "Works correctly" is not an expected result.
- **Say how failure looks**, not only how success looks. The reader must be able to tell the difference without asking.

## Anatomy of a test case

Two layouts. Use the table for API and shell cases — they are request-and-answer and read best in two
columns. Use numbered prose for interface cases, with each step carrying **its own** expected result after an
arrow. Never write steps in one block and expectations in another: making the reader match "Step 4" against a
bullet that says "Step 4:" is the single biggest thing that makes a plan hard to follow.

**Interface case:**

```
### T-<n> · <short title in plain words>

**Surface:** UI (add "+ devtools Network tab" or "+ a real mail client" when needed)
**Where:** <exact screen path or URL>
**Priority:** P1 | P2 | P3
**In one line:** <what this case does, so the reader can plan without reading on>
**Set up:** <accounts and roles> · <data state> · <anything to write down first>

<at most two sentences on what changed, in product terms>

1. <action> → <what you should see>
2. <action> → <what you should see>
3. <action> → **<what you should see, emphasised when this is the point of the case>**

**Fail looks like**
- <the specific wrong outcome, and which of them matters most>

**Changed**

| | Previous | New |
|---|---|---|
| <the thing a user does> | <old outcome> | <new outcome> |
```

**API or shell case:**

```
### T-<n> · <short title in plain words>

**Surface:** API client only — <name the project's client and environment>. <Say why no screen reaches it.>
**Where:** <method and path, or command name>
**Priority:** P1 | P2 | P3
**In one line:** <what this case does>
**Set up:** <accounts> · <data> · <ids and passwords needed>

| # | Send this | Expect |
|---|---|---|
| 1 | <request, with the varying part named> | <status and body, exactly> |
| 2 | <request> | <status and body, exactly> |

**Fail looks like** <the specific wrong outcome>
```

Where a case mixes surfaces, mark the switch on the step rather than in the header alone — the reader is
partway through and needs to know a different tool is now required.

Replace the **Changed** table with the note **Regression check** when nothing should have changed; then seeing
the old behaviour is the pass, and the reader must not mistake it for a finding.

Older cases in an existing document may use this longer form; it is still valid but harder to follow:

```
**Area:** <feature> · **Priority:** P1
**Why it needs checking:** <one sentence>

**Before you start**
- <account and role needed>
- <record / project / data state needed>

**Steps**
1. <action>

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

## Three case shapes that are easy to miss

**The permissive half of a permission split.** When a guard splits into "the public path refuses, the internal
path allows", the case that matters most is that the **allowed** path still works. Breaking it locks out
legitimate users, which is worse than the hole that was closed — and it is the half nobody writes a case for,
because the change was framed as a restriction. Put that step first, emphasise it, and say in the failure
notes which of the two failures matters more.

**Double-encoding, the symmetric regression of any escaping fix.** Every case about escaping user text needs
both failure directions: the markup rendering as markup (the fault being fixed), **and** the user seeing
`&amp;` or `&#039;` where they typed `&` or `'` (the fault the fix introduces). A case that checks only the
first will pass on a build that shows every apostrophe as an entity.

**A payload whose shape changed, not just its fields.** When a response or a page's settings are re-serialised
rather than edited field by field, the risk is not a wrong value — it is a screen that does not render at all.
Write a case that opens **every** page or screen the payload feeds, and say that a blank area or a script error
is the failure. Field-level checks will not find it.

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
