# Manual test plan — <release or change-set name>

**Covers:** `<BASE>` → `<HEAD>` (<n> commits, <n> changed files, <n> submodule pointers)
**Prepared:** <date>
**Environment:** <environment and URL, plus anything that must not be shared with another branch>

## How to read a case

Each case carries the same header:

- **Surface** — where you do the work: the browser interface, an API client, a mail client, or a shell.
  Check this first; it tells you whether you need a tool open before you start.
- **Where** — the exact address or screen.
- **In one line** — what the case does, so you can plan without reading further.
- **Set up** — what must exist before step 1.

Then the steps. Every step carries its own expected result after an arrow (`→`), so nothing has to be
matched up against a separate list. API and shell cases are laid out as a table of request and
expected answer.

Each case ends with **Fail looks like** and either a **Changed** table — the old behaviour is no
longer correct — or the note **Regression check**, meaning nothing should have changed and seeing the
old behaviour is the pass.

Record the case ID and the outcome. A partial match is a failure: stop and report it with the ID.

### Tools

<!-- Name the project's own conventions. Delete the lines that do not apply. -->
- **API client:** <the project's client and environment; say if curl is discouraged>
- **Mail client:** <cases needing a real client rather than a raw message view>
- **Shell:** <cases needing to run commands on the instance>
- **Browser devtools:** <cases checking a response rather than a screen>

### Accounts and data used throughout

| Name | What it must be |
|---|---|
| **<role>** | <what it must own or belong to> |

---

## Case index

<!-- A tester should be able to plan the whole session from this table without reading a case. -->

| ID | Surface | In one line | Priority |
|---|---|---|---|
| T-1 | <surface> | <one line> | P1 |

**Cases you cannot start without a tool:** <list them, so nobody discovers it at step 1>

---

## Test cases

<!--
One block per case, highest priority first. Two layouts — see references/writing-test-cases.md.
Never write steps in one block and expectations in another: making the reader match "Step 4" against
a bullet beginning "Step 4:" is the single biggest thing that makes a plan hard to follow.
-->

### T-1 · <short title in plain words>

**Surface:** UI <add "+ devtools Network tab" or "+ a real mail client" when needed>
**Where:** <exact screen path or URL>
**Priority:** P1
**In one line:** <what this case does>
**Set up:** <accounts and roles> · <data state> · <anything to write down first>

<at most two sentences on what changed, in product terms>

1. <action> → <what you should see>
2. <action> → <what you should see>
3. <action> → **<what you should see, emphasised when this is the point of the case>**

**Fail looks like**
- <the specific wrong outcome; say which matters most when there is more than one>

**Changed**

| | Previous | New |
|---|---|---|
| <the thing a user does> | <old outcome> | <new outcome> |

---

### T-2 · <short title in plain words>

**Surface:** API client only — <client and environment>. <Say why no screen reaches this.>
**Where:** <method and path>
**Priority:** P2
**In one line:** <what this case does>
**Set up:** <accounts> · <ids and passwords needed>

<at most two sentences on what changed>

| # | Send this | Expect |
|---|---|---|
| 1 | <request, with the varying part named> | <status and body, exactly> |
| 2 | <request> | <status and body, exactly> |

**Fail looks like** <the specific wrong outcome>

**Changed**

| | Previous | New |
|---|---|---|
| <the situation> | <old outcome> | <new outcome> |

---

## Changed but not manually testable

These changed in this release and were reviewed. None of them can alter what a user sees, for the
reason given.

<!--
Enumerate. A glob such as `src/views/**` reads as coverage and hides every file beneath it —
scripts/verify_coverage.sh will not accept it, and neither should a reader.
-->

| File or area | Reason it needs no manual check |
|---|---|
| `<path>` | <specific reason — never just "refactor"> |

## Open questions for the developer

Each needs an answer before its area can be signed off.

| # | Question | Why it blocks testing |
|---|---|---|
| Q-1 | <question> | <what cannot be reached or confirmed without it> |

## Appendix — traceability

For reference when reporting a problem. Not needed to run the tests.

| Case | Changed files behind it |
|---|---|
| T-1 | `<path>` |
