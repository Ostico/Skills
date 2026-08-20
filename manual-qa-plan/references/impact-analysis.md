# Deciding what needs manual testing

Contents: [Verdict rule](#every-changed-file-gets-a-verdict) · [Reading the change](#reading-what-actually-changed) ·
[Invisible-change traps](#changes-that-reach-the-user-without-looking-like-it) · [Priority](#assigning-priority) ·
[Preconditions](#preconditions-and-test-data)

## Every changed file gets a verdict

The report is only trustworthy if nothing was skipped silently. Assign each changed file exactly one verdict:

| Verdict | Meaning | Goes in the document as |
|---|---|---|
| **TESTABLE** | A person can observe this change through the product | One or more test cases |
| **NOT USER-VISIBLE** | Cannot change what any user sees or receives | A one-line entry in "Changed but not manually testable", with the reason |
| **NEEDS DEV INPUT** | Reaching it manually is unclear or may be impossible | An entry in "Open questions for the developer", with the specific question |

Never drop a file. `NOT USER-VISIBLE` requires a stated reason — "refactor" alone is not a reason; "renamed a private variable, no call sites outside the file" is.

Test-only changes are `NOT USER-VISIBLE`, with one exception: a **deleted** test may mean deleted behaviour. Check what it covered.

## Reading what actually changed

For each behaviour change, get both sides before writing a test case:

```bash
git show <BASE>:path/to/file.ext        # previous
git show <HEAD>:path/to/file.ext        # current
git log -p <BASE>..<HEAD> -- path/to/file.ext   # why, commit by commit
```

The commit message says intent; the diff says what shipped. When they disagree, the diff wins and the disagreement is an open question.

Trace outward from each changed function to the screen or endpoint that reaches it. If nothing reaches it, that is evidence for `NOT USER-VISIBLE` — say how you checked.

## Changes that reach the user without looking like it

These are the ones a diff-reader misses. Check each against the risk flags:

| Change | What the person must actually do to see it |
|---|---|
| Cache added, removed, or keyed differently | Do the action **twice**, and as **two different users**. Stale or cross-user data shows only on the second look. |
| Background job / queue / worker | Act, then **wait** and re-check. Say how long. A result that never arrives is the failure, and it looks like nothing happening. |
| Database migration | Test on data that **already existed** before the change, not only on records created fresh afterwards. |
| Index added or removed | Watch for a page that got slow, or a list whose **order** changed when no sort was requested. |
| Default value changed | Existing records keep the old value, new ones get the new one. Check both. |
| Permission / role / ownership check | Test as someone who **should not** have access. Success is being refused. |
| Validation rule | Test the rejected input too, and read the exact message shown. |
| Retry / timeout / rate limit | Repeat the action quickly, several times. |
| Email or notification template | The change is only visible in the message that arrives — open it. |
| Third-party dependency bump | Exercise the feature that uses it; the dependency's own behaviour may have moved. |
| Locale / date / number formatting | Check in a second language and a second timezone. |
| Error path | Force the error deliberately. Untested error paths are where regressions hide. |
| Submodule pointer moved | The real change is inside the submodule — inspect there or raise it as an open question. |

## Assigning priority

- **P1** — a person doing normal work would hit it, or the change touches money, permissions, or data integrity.
- **P2** — reachable in normal use but off the main path, or a less common configuration.
- **P3** — cosmetic, or an edge case that needs deliberate setup.

Existing automated test coverage **lowers priority by one step; it never removes the item.** Automated tests check the code as written, not the product as used.

## Preconditions and test data

A step that cannot be reached is not a test. For every case, state what must exist first: the account and its role, the project or record state, any feature flag, the environment. If reaching the state needs a database change or an unusual setup, put it under "Open questions for the developer" rather than writing steps nobody can follow.
