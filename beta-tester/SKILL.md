---
name: beta-tester
description: Use when asked to "beta test", "QA", "manually test", "test in the browser" or "click through" a feature, page or flow of a running web app, or to exercise an API endpoint against its spec — e.g. "beta test the checkout flow", "QA signup against PR 482", "test POST /api/v1/orders against the spec". Drives a real browser (UI) or sends real HTTP requests (API) and reports the bugs it confirms. NOT for running the project's own automated test suite, NOT for writing a manual test-plan document (that's manual-qa-plan), and NOT for CLI commands or background workers that neither a browser nor an HTTP client can reach.
---

# Beta test a running application

Read whatever conventions the project already states — a `CLAUDE.md`, `CONTRIBUTING.md`, README,
or style guide — before testing: they tell you where this codebase's bugs actually cluster, and
they may define the oracle for copy or style findings (see `references/bug-shapes.md`).

## Usage

Ask for something to be tested and it exercises it for real — driving a browser through a UI
surface the way a person would, or firing real HTTP requests at an API endpoint — then reports
what it found.

```
/beta-tester <what you want tested>
```

**Two inputs are needed before anything runs: a target and an oracle.** The target is a URL (or a
clear "the app already running at ..."); the oracle is the source of truth for expected behaviour
(see "Establishing the oracle"). There is no default host and no environment-tier argument — the
target is whatever the user gives, and the skill does not judge or refuse it, nor check that it is
up. See "Fail fast, not pre-flight" below. It does check one thing: that the target runs the code
the oracle describes (see "Make sure the target runs the code under test").

Some examples:

```
/beta-tester test signup at https://app.example.com and check the welcome email arrives
/beta-tester QA the checkout flow on https://staging.example.com against PR #482
/beta-tester test POST /v1/orders on https://api.example.com against the OpenAPI spec
```

### Intake — ask once, together

Ask the up-front questions in **one** message (several questions in one structured prompt where
the harness offers one), so an unattended run doesn't stop five times:

- the target, if the task didn't give one
- the oracle, if the task didn't give one
- whether confirmed findings should be filed, and where (see `references/filing-findings.md`)

Skip any question the task already answers. The persona is asked separately, once the checklist
exists (workflow step 2): only the checklist says whether a second persona is needed. Questions
that can only arise mid-run — logging the user out, a download, an irreversible action — are
asked when they arise, never pre-emptively.

### UI mode and API mode

There is no mode argument. The skill infers it from what was asked and **states it back before
doing anything**, the same way it states the target:

| you named | mode | acting mechanism |
|---|---|---|
| a page, panel, screen, or user flow | **UI** | a real browser |
| an endpoint, route, or documented API operation | **API** | real HTTP requests |
| both, or a flow that crosses them | whichever was named first, and it says when it switches | both |

A run that starts in the browser often ends in API mode for one finding — the UI is where a bug
shows itself and the API is where its shape gets pinned down. That is normal. Every finding
records which mechanism produced it.

## Fail fast, not pre-flight

This skill does not verify the target before starting. No DNS resolution, no health check, no
readiness probe, no framework-specific staleness check. It asks for the target URL once, if the
task didn't supply one, then goes straight into the first real step of the checklist. The one
check it does make is not about the target being up but about it running the right code — see
"Make sure the target runs the code under test".

A refused connection, a DNS failure, a 404 where the app should be, a TLS error, a login that
doesn't work — none of these are setup chores to silently work around or explain away. Report
each one immediately as **`[BLOCKED]`** and stop; let the user decide whether to fix the target or
give a different one. `[BLOCKED]` is not a finding about the product: it is never scored and never
filed.

A refusal from **your own client** is not the target failing. `bruno-mcp`, for example, refuses
loopback and private addresses with `SSRF blocked` and status 0 unless its operator allowlisted
them. Say which client refused, then switch client (see `references/api-mode.md`) rather than
reporting the target as down.

There is no environment-tier concept — no `local`/`staging`/`production` argument, and no refusal
based on one. The user chose the target; that choice is theirs to make, and the skill acts on it.
If the target is obviously shared with other people — a colleague's staging box, a shared demo
environment — apply ordinary courtesy without being asked: prefix anything created so it's
identifiable, avoid actions whose blast radius reaches other users (rate-limit storms, concurrency
storms, session tampering), and clean up before the summary. A task that asks for exactly such a
probe still passes through the gate below: the task names the probe, and the gate confirms it on
this target.

### The one gate that survives: irreversible or outward-facing actions

Whatever the target — localhost included, since a local app can still send real email or charge a
real card — ask before any action that cannot be undone or that reaches someone outside the run:

- a real payment, charge, refund, or anything else that moves money
- an email, SMS, or notification to an address the run doesn't own
- deleting or overwriting data the run didn't create
- a rate, burst, or concurrency probe on a target that isn't exclusively yours
- tampering with a session that isn't one of the run's own personas, on a target that isn't
  exclusively yours

Name the action and its effect, and act only on a yes. Prefer the target's own test means where
they exist: a sandbox payment mode with test card numbers, a plus-addressed or catch-all inbox, the
project's dev mail catcher.

**A flow that sends email** needs an inbox the run can actually read — a mailbox reachable through
a connector in this session, a dev mail catcher (MailHog, Mailpit, ...), or the user confirming
receipt. No way to read it → that assertion is `NOT RUN`, never a pass.

## Golden rule: use the real mechanism for the mode

Whatever the mode, the thing under test is **exercised for real, against a running target**. A
simulation is never a substitute, and a regression test is only ever an *output artifact*, written
after a bug has been confirmed by hand — see `references/regression-artifact.md`.

**UI mode — a real browser**, driven step by step through your agent harness's live browser
integration (in Claude Code, `claude --chrome` plus the Claude-in-Chrome extension; other
harnesses expose their own equivalent, such as a Playwright MCP server — discover what's available
in this session rather than assuming a name). A **pre-written** Playwright/Puppeteer script is
**never** the acting mechanism: it runs blind, so it cannot react to what the page actually shows,
and that reaction is the point of a beta test.

- If browser tools aren't available in this session, **stop** and tell the user how to attach
  one. Do not fall back to writing a script and pretending it ran.
- Browser tool names are often undocumented ahead of time — discover them at runtime.

**API mode — real HTTP requests** against the running target, authenticated as the chosen
persona. Never a mocked response, and never a reading of the server's source code presented as a
result: the whole point is what the deployed code actually returns. A missing browser is not a
blocker here.

### Mechanics that bite (UI mode)

- **A native dialog freezes the browser tool.** `alert()`, `confirm()`, `prompt()` and a
  `beforeunload` prompt block every later browser command until a human dismisses them — and
  delete buttons, cleanup, and leaving a half-filled form all raise them. Before clicking
  something likely to open one, warn the user. If one opens anyway, tell the user to dismiss it
  by hand.
- **A transient menu closes when you look for it.** A dropdown, popover, or context menu opened
  by a click is often gone by the time a locator/`find` call returns a reference to an element
  inside it. Screenshot the open menu and interact by coordinate instead of searching for an
  element mid-interaction.
- **A protected page can refuse a credential smuggled through the URL.** Building a link that
  carries a token, password, or session id in a query string is often blocked by the browser tool
  itself, and correctly so. Get the same evidence from the app's own control, which already holds
  the session, rather than working around the block.
- **The browser is the user's real profile.** "Sign in with Google/GitHub/...", a payment wallet,
  or any other third-party flow acts there as the user's own real identity. Don't drive one unless
  the task names it, and ask before you do.
- **Downloading a file needs the user's permission, every time.** Inspecting a download is often
  the only real proof a feature works, and it's also the one step that writes to their disk. Ask
  first, naming the file, the source, and the size — and resolve the real downloads directory
  rather than assuming `~/Downloads`: the browser's own download setting decides, and
  `xdg-user-dir DOWNLOAD` on Linux is only the system default.

## Establishing the oracle

**Never invent expectations.** Before touching anything, name the source of truth for "expected"
— the **oracle**. It can be:

- a PR or issue link, on any forge (GitHub, GitLab, Bitbucket, ...)
- a task or card on a tracker — Asana, Notion, Jira, Linear, or whatever the team uses
- a written spec — a machine-readable one (OpenAPI/Swagger, a GraphQL schema) or a plain document
- observed behaviour on a reference environment, for a regression
- a documented contract in the project itself (a `CLAUDE.md`, a style guide, a README)
- simply the user's own description of what should happen, ideally with a PR link attached — this
  is a complete and legitimate oracle on its own, not a fallback of last resort

**Recognising it.** Look for a URL anywhere in the request. A PR/issue link is read with `gh` or
the forge's own tool; a tracker card is read with whatever connector for that platform exists in
this session (Asana, Notion, Jira, Linear, ...). **No connector for a named platform → say so in
one line and fall back to asking the user directly** — do not treat the absence of a connector as
the absence of an oracle.

**Reading it.** Pull out the acceptance criteria (or the reported repro, if it's a bug report),
the linked PR/diff if any, and the surface it touches. A card or issue is **read-only**: never
comment on it, never edit it, never move it — that's the human's step. Filing a *new* finding is a
different action, governed by `references/filing-findings.md`.

**Intent vs. implementation.** The oracle says what was asked for; a linked diff or the live code
says what was built. Read both when both exist — where they explicitly disagree, that
disagreement is itself the finding.

**Oracles go stale.** Read comments and discussion before treating a description as final — the
last word wins. Where two parts of the oracle disagree, say which one was tested against.

**Make sure the target runs the code under test.** If the oracle names a branch or PR:

- **The target is something checkable out and run locally** → offer to switch to it before
  testing, and switch only on explicit confirmation, since changing a working tree is not
  something to do silently. Run `git status` first: uncommitted work in the tree is the user's,
  so say what's there and stash or commit it only with their consent. After a switch this run
  made, do whatever the project needs for the target to serve the new code — rebuild front-end
  assets, restart a dev server — and ask how if it isn't obvious. That is finishing the switch,
  not a pre-flight check. The same applies to a switch for a control run (workflow step 5), and
  step 10 offers to undo every switch.
- **Otherwise** → before the first assertion, compare the target's version signal (workflow step
  1) with the PR's head commit, or look for the change itself on the target. No way to tell → ask
  once. A target that doesn't carry the change makes every missing feature look like a bug.

**They don't match → `[BLOCKED]`, and stop.** Name what the target runs and what the oracle
describes, and let the user redeploy or point at another target.

**No anchor for a given assertion → report it as an `[OBSERVATION]`, unscored, never filed.** The
task names no oracle at all → ask once, up front. The user declines to give one → run
**exploratory**: every result is an `[OBSERVATION]`, nothing is scored or filed, and the header
says so. Inventing expectations is the single largest source of false bug reports.

## Accounts and personas

**The logged-in account can change what the app does** — plan tiers, roles, and feature flags
commonly gate behaviour per account. Testing a gated change as a plain account often doesn't fail
loudly: it just exercises core behaviour and reports a clean pass. So the account is chosen
deliberately, its state is confirmed before the first assertion, and it's recorded on every
finding. A cross-persona shape — AUTHZ, TAMPER, ENTITLEMENT — needs a **second** persona to play
the other caller or the other entitlement; both are asked for together, in workflow step 2.

Full mechanics — where credentials live, how personas are discovered, using a credential without
showing it, logging in and proving the right account is actually active, and the "frozen
entitlements" trap — are in `references/accounts-and-credentials.md`. Read it before the first
login or the first authenticated request.

## API mode

Full mechanics — authenticating, verifying credentials once, authoring and running requests with
`bruno-mcp` when it's available (for personas with permission to hand it their credentials), using a spec as oracle, and cleaning up what was created — are in
`references/api-mode.md`. Read it before the first authenticated request.

## What counts as a "feature" here

- A front-end surface: a page, a panel, a sidebar, a list view, an active editing state.
- An API surface: one endpoint, or a group of them that share a resource or a controller.
- An end-to-end flow crossing several of either — sign up → create a resource → act on it →
  observe the result.

**When a UI bug points at the backend**, the browser found it and API mode characterises it: same
run, switch mechanism, say that you switched, and tag the finding with the mechanism that produced
it.

**Out of scope:** CLI commands, background workers, and anything else neither a browser nor an
HTTP client can reach.

## Execution workflow

Given a testing task, or a link to an oracle:

0. **Intake, then the oracle** — ask the up-front questions in one message (see "Intake"), and
   establish the oracle before anything else (see "Establishing the oracle").
1. **Resolve the target.** The first real action *is* the reachability check — there is no
   separate verification step (see "Fail fast, not pre-flight"). If the target exposes a version
   signal — a commit SHA, a build banner, a version field — note it now. Then scope the task into
   a bounded, explicit checklist **before** touching the browser or sending the first request.
   This is the main lever for token efficiency — if the request is combinatorially large (every
   field × every panel × both modes), state the resulting checklist size and structure back to the
   user before grinding through it, rather than silently grinding through it.
2. **Choose the account, authenticate, and confirm its state** — see
   `references/accounts-and-credentials.md`. Ask for the persona now, in one question, together
   with a second one if the checklist holds a cross-persona shape (AUTHZ, TAMPER, ENTITLEMENT).
   In UI mode, decide in the same message how the browser logs in — order the checklist by
   persona, move the second persona to API mode where it doesn't need the UI, and ask about the
   login method only if browser switches remain (see "How the browser gets logged in"). State the
   persona, how it logged in, and what was confirmed about it in the header block; a run that
   doesn't say which account produced a finding is not reproducible.
3. **Happy path first.** Walk the checklist's core flow end-to-end exactly as a normal caller
   would — real clicks/typing/navigation in UI mode, real requests in API mode. Confirm it before
   doing anything adversarial.
4. **Then dig into edge cases, deliberately trying to break it** — use
   `references/bug-shapes.md` as a generator. The irreversible-action gate applies to every probe.

   **Keep a ledger from the first request on**, in both modes: every resource the run creates —
   its kind, its id or name, the persona that owns it. Step 10 works from it, and it is what the
   summary lists when something couldn't be removed.
5. **Attribute before you score — run the control.** The control is the same scenario without
   the change under test:
   - a flag, toggle, or setting → the same scenario with it **off**. On a shared target, turning
     it off changes it for everyone, so ask first.
   - a PR → the base version: a reference environment, or the base branch — a branch switch,
     with the same confirm-and-rebuild rule as any other (see "Make sure the target runs the
     code under test"), which step 10 offers to undo.
   - a suspected regression → the last version where it worked. The REGRESSION floor needs this
     evidence, not a hunch.

   The delta between the two runs *is* the finding; whatever is common to both belongs to the
   base, not to the change under test. No control available → say so, report findings as
   unattributed, and don't apply the REGRESSION floor.
6. **Report each confirmed bug as soon as it's found** — don't batch everything to the end. Score
   it per the model below; while its control run is still pending, mark the score provisional,
   and restate it once the control has run.
7. **For `[CRITICAL]`/`[HIGH]` bugs, offer the regression test** — see
   `references/regression-artifact.md`. It goes into the user's working tree, so write it only on
   a yes. `[MEDIUM]`/`[LOW]` are reported but not spec'd unless asked.
8. **Offer to file eligible findings** — see `references/filing-findings.md`. Draft each one,
   show it, and create only on a yes.
9. **Re-check the version signal**, if step 1 found one. Changed mid-run → say so and mark which
   findings predate the change. No signal → skip this step, don't invent one.
10. **Clean up.** Remove everything in the ledger, and everything else the run created:
    - **Resources on the target** → through its API wherever it offers deletion, even after a UI
      run: deleting through the UI raises `confirm()` dialogs, and each one freezes the browser
      tool until a human dismisses it. Use the UI only where the API can't do it, and warn first.
    - **The run's own files** → any curl cookie jar, and the `bruno-mcp` collection and
      environment authored for this run (see "Cleaning up" in `references/api-mode.md`).
    - **A regression test written in step 7** → settle it with the user before any switch back
      (see `references/regression-artifact.md`).
    - **A branch switched or something checked out for this run** → offer to switch back, and
      restore a stash made with the user's consent — offer, don't just do it.

    Anything that couldn't be removed is listed in the summary, with where it lives. Then close
    with the summary.

**Stop condition.** The checklist is the budget. When it's exhausted — or about 3–5 edge cases per
item have been spent — stop and report. Do not wander. If the remaining surface seems worth more
time, say so and let the user decide.

## Bug shapes — use these as the generator

Don't wait to be told what to try. The full catalogue — COPY, NAMES, I18N, PERSIST, LISTS, STALE, ASYNC,
SILENT, ENTITLEMENT, the UI-mode additions (TAMPER, INJECT, NAV, A11Y), and the API-mode additions
(SPEC, STATUS, AUTHZ, TYPES, PAGINATION, RATE) — is in `references/bug-shapes.md`. Read it before
the adversarial pass (workflow step 4).

## Token efficiency

- The upfront checklist is the main budget control — use it to avoid open-ended wandering.
- Screenshot only at decision points or as bug evidence, not after every single action.
- **Never keep a screenshot that shows a credential**: a token or session id in the address bar,
  a DevTools panel with cookies or request headers, a password field revealed as text, an API key
  on a settings page. Retake it without, or describe the screen instead.
- Batch same-page checks into one navigation instead of re-navigating per assertion.
- For repetitive sweeps (e.g. "test every field type"), report terse one-line pass confirmations
  per item and only expand detail where something actually failed.

## Reporting

### Header block

Stated before the first step, and updated whenever one of its lines changes:

```
Target    <URL>
Mode      UI | API | both — and why
Oracle    <source> — or "none: exploratory run"
Account   <persona> · <how: already signed in | user logged in | typed (TYPED or a yes) |
          token or login over bruno-mcp or direct HTTP> · <what was confirmed about its state>
Client    per persona: bruno-mcp | direct HTTP — API mode only
Version   <signal> — or "none exposed"
Checklist <N items>: <item> · <item> · ...
```

### Result labels

| label | meaning | scored | filed |
|---|---|---|---|
| `[CRITICAL]` `[HIGH]` `[MEDIUM]` `[LOW]` | a confirmed bug, measured against the oracle | yes | see filing |
| `[OBSERVATION]` | something odd with no oracle to measure it against | no | never |
| `[BLOCKED]` | the run couldn't reach or use the target (environment, credentials, client) | no | never |

### Bugs

For each confirmed bug:

- Severity label: `[CRITICAL]` / `[HIGH]` / `[MEDIUM]` / `[LOW]`
- The mode that produced it — UI or API — since a run may use both
- BUG_SCORE + factor breakdown, and any floor that was applied
- The oracle the expectation came from
- The account it was found under, and what was confirmed about its state
- The control run: does it still reproduce with the change absent? Unattributed findings say so
- Steps to reproduce
- Expected vs. actual

### Summary

| Item | Status | Notes |
|---|---|---|

Status is one of:

- `PASS` — matched the oracle
- `FAIL` — with the bug's label
- `OBSERVED` — produced only `[OBSERVATION]`s, so there was no oracle to pass or fail against
  (every item of an exploratory run)
- `BLOCKED`
- `NOT RUN` — with why: out of budget, no inbox to read, a gate the user declined, no second
  persona

Below the table, list:

- anything discounted as noise of your own setup, and why
- resources the run created and could not remove
- whether the version signal changed during the run

## Filing findings

Confirmed findings can be filed somewhere the team will see them. Never file without showing the
draft and getting a yes, and never file a security finding where people outside the project can
read it. Full workflow — asking where, if anywhere, matching the target workspace's own
conventions, the eligibility table, security disclosure, and the duplicate-check discipline — is
in `references/filing-findings.md`.

## Bug prioritization model

```
BUG_SCORE = IMPACT × REPRODUCIBILITY × SURFACE          (1–75)
Severity  = the higher of (score tier, floor tier)
```

| | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| **IMPACT** | cosmetic | degraded or confusing, outcome still correct | a secondary feature broken or a wrong result | a core flow broken, a workaround exists | crash, data loss, security, or a core flow blocked with no workaround |
| **REPRODUCIBILITY** | reproduced once, trigger unclear | occasionally, trigger known | about half the attempts | most attempts | every attempt |
| **SURFACE** | an edge configuration few reach | a segment — one plan, role, locale, or browser | every user, or every caller of the endpoint | | |

| score | tier |
|---|---|
| ≥ 45 | `[CRITICAL]` |
| ≥ 24 | `[HIGH]` |
| ≥ 10 | `[MEDIUM]` |
| < 10 | `[LOW]` |

**Floors** — applied regardless of score, because a multiplied score under-weights them:

| condition | floor |
|---|---|
| SECURITY — a security risk | at least `[HIGH]` |
| DATA_LOSS — data corruption or loss | at least `[HIGH]` |
| REGRESSION — a previously working feature broken, shown by a control run | at least `[MEDIUM]` |
| SECURITY **and** DATA_LOSS together | `[CRITICAL]` |

Reporting and scoring must always agree: state the score, the factors, and any floor applied.

## Examples

**No target, no oracle given** — every intake question goes out in one message:

> *beta test the checkout flow*

```
Three things before I start:
1. What URL is this running at?
2. What's the source of truth for how checkout should behave — a PR, a spec, a ticket, or
   your own description of the expected flow?
3. Should confirmed bugs be filed somewhere (a tracker, GitHub issues), or only reported here?
```

**Target and oracle both given, UI mode inferred:**

> *beta test https://app.example.com/checkout against https://github.com/acme/shop/pull/482*

```
Target    https://app.example.com/checkout
Mode      UI — a page was named
Oracle    PR #482 — "Add saved-card checkout"
Version   build banner a1b2c3d — matches the PR head

Checklist — 5 items: happy-path checkout with a saved card · add a new card
mid-checkout · remove the only saved card · expired card at submit · empty
cart. Payments run in the sandbox with test cards; I'll confirm with you before
the first charge if the sandbox isn't available.

No cross-persona item, so one account is enough. Which persona should I test as?
Configured: DEFAULT (plain account) · PAID (paid tier with the gated feature set).
```

The task named the target and the oracle, so intake asked only whether to file findings, and
that was answered before this point. Only the persona is asked here; the answer fills the
`Account` line, and the run starts on the happy path.

**API mode, inferred from the endpoint, `bruno-mcp` authoring a collection on the fly:**

> */beta-tester QA POST /v1/orders on https://api.example.com against the OpenAPI spec*

```
Target    https://api.example.com/v1/orders
Mode      API — an endpoint was named. Browser not required, not attached, not a problem.
Client    DEFAULT bruno-mcp (TYPED), authoring a collection · OTHER direct HTTP (no TYPED)
Account   DEFAULT · token, TYPED · verified once ✓ · OTHER · token over direct HTTP, second
          caller for the authz probe
Oracle    the project's openapi.json, operation POST /v1/orders
Version   none exposed

Checklist — 6 items: happy-path create · documented-vs-accepted parameter
sweep · omit each mandatory field · malformed body · OTHER's token against
DEFAULT's order · error-payload shape check. Everything created is cancelled
before the summary.
```
