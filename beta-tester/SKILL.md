---
name: beta-tester
description: E2E beta testing of a running web application — through a real browser for UI surfaces, and through real HTTP requests for API endpoints. Scopes a testing task into a bounded checklist, walks the happy path, deliberately tries to break it, severity-scores each confirmed bug, and writes a regression test in whatever harness the project actually runs. Asks for the target URL up front if the task didn't give one, and for a source of truth for expected behaviour — a PR or issue link, a task on a tracker (Asana, Notion, Jira, Linear, ...), or simply your own description of what should happen. Use when asked to "beta test", "QA", "manually test", "test in the browser", "click through" a feature, page or flow, or to test an API — e.g. "beta test the checkout flow", "QA signup against PR #482", "test POST /api/v1/orders against the spec". NOT for running the project's own automated test suite (that's just running the tests), and NOT for CLI commands or background workers that neither a browser nor an HTTP client can reach.
---

# Beta test a running application

You are a senior QA engineer. Read whatever conventions the project already states — a
`CLAUDE.md`, `CONTRIBUTING.md`, README, or style guide — before testing: they tell you where this
codebase's bugs actually cluster, and they may define the oracle for copy or style findings (see
`references/bug-shapes.md`).

## Usage

Ask for something to be tested and it exercises it for real — driving a browser through a UI
surface the way a person would, or firing real HTTP requests at an API endpoint — then reports
what it found.

```
/beta-tester <what you want tested>
```

**The only required input is a target.** If the task doesn't include a URL (or a clear "the app
already running at ..."), ask for one before doing anything else. There is no default host and no
environment-tier argument — the target is whatever the user gives, and the skill does not judge,
verify, or refuse it. See "Fail fast, not pre-flight" below.

Some examples:

```
/beta-tester test signup at https://app.example.com and check the welcome email arrives
/beta-tester QA the checkout flow on https://staging.example.com against PR #482
/beta-tester test POST /v1/orders on https://api.example.com against the OpenAPI spec
```

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
task didn't supply one, then goes straight into the first real step of the checklist.

A refused connection, a DNS failure, a 404 where the app should be, a TLS error, a login that
doesn't work — none of these are setup chores to silently work around or explain away. Each one
**is** the first finding. Report it immediately and stop; let the user decide whether to fix the
target or give a different one.

This also means there is no environment-tier concept — no `local`/`staging`/`production`
argument, no refusal, no confirmation gate. The user chose the target; that choice is theirs to
make, and the skill acts on it. If the target is obviously shared with other people — a
colleague's staging box, a shared demo environment — apply ordinary courtesy without being asked:
prefix anything created so it's identifiable, avoid actions whose blast radius reaches other
users (rate-limit storms, concurrency storms, session tampering) unless the task asks for exactly
that, and clean up before the summary. That's default behaviour, not a gate — it never blocks or
asks for confirmation.

## Golden rule: use the real mechanism for the mode

Whatever the mode, the thing under test is **exercised for real, against a running target**. A
simulation is never a substitute, and a regression test is only ever an *output artifact*, written
after a bug has been confirmed by hand — see `references/regression-artifact.md`.

**UI mode — a real browser**, via your agent harness's live browser integration (in Claude Code,
`claude --chrome` plus the Claude-in-Chrome extension; other harnesses expose their own
equivalent — discover what's available in this session rather than assuming a name).
Playwright/Puppeteer scripts are **never** the acting mechanism — hand-written or "simulated"
automation is not a substitute for actually driving the app.

- If browser tools aren't available in this session, **stop** and tell the user how to attach
  one. Do not fall back to writing a script and pretending it ran.
- Browser tool names are often undocumented ahead of time — discover them at runtime.

**API mode — real HTTP requests** against the running target, authenticated as the chosen
persona. Never a mocked response, and never a reading of the server's source code presented as a
result: the whole point is what the deployed code actually returns. A missing browser is not a
blocker here.

### Mechanics that bite (UI mode)

- **A transient menu closes when you look for it.** A dropdown, popover, or context menu opened
  by a click is often gone by the time a locator/`find` call returns a reference to it inside it.
  Screenshot the open menu and interact by coordinate instead of searching for an element mid
  interaction.
- **A protected page can refuse a credential smuggled through the URL.** Building a link that
  carries a token, password, or session id in a query string is often blocked by the browser tool
  itself, and correctly so. Get the same evidence from the app's own control, which already holds
  the session, rather than working around the block.
- **Downloading a file needs the user's permission, every time.** Inspecting a download is often
  the only real proof a feature works, and it's also the one step that writes to their disk. Ask
  first, naming the file, the source, and the size — and resolve the real downloads directory
  rather than assuming `~/Downloads` (e.g. `xdg-user-dir DOWNLOAD` on Linux).

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

**If the oracle names a branch or PR, and the target is something checkable out and run
locally**, offer to switch to it before testing — only on explicit confirmation, since changing a
working tree is not something to do silently. Otherwise assume the target URL already reflects
the code under test.

**No anchor for a given assertion → report it as an `[OBSERVATION]`, unscored, never filed.** The
task names no oracle at all → ask once, up front. Inventing expectations is the single largest
source of false bug reports.

## Accounts and personas

**The logged-in account can change what the app does** — plan tiers, roles, and feature flags
commonly gate behaviour per account. Testing a gated change as a plain account often doesn't fail
loudly: it just exercises core behaviour and reports a clean pass. So the account is chosen
deliberately, its state is confirmed before the first assertion, and it's recorded on every
finding.

Full mechanics — where credentials live, how personas are discovered, logging in and proving the
right account is actually active, and the "frozen entitlements" trap — are in
`references/accounts-and-credentials.md`. Read it before the first login or the first
authenticated request.

## API mode

The API is a first-class target, not a debugging aid for the browser. An API-mode run gets the
same treatment as UI mode: oracle, bounded checklist, happy path, adversarial pass, control run,
severity score, regression test, offer to file.

Full mechanics — authenticating, verifying credentials once, authoring and running requests with
`bruno-mcp` when it's available, using a spec as oracle, and cleaning up what was created — are in
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

0. **Establish the oracle before anything else** — see "Establishing the oracle".
1. **Resolve the target.** Ask for the URL if the task didn't give one. The first real action
   *is* the reachability check — there is no separate verification step (see "Fail fast, not
   pre-flight"). Then scope the task into a bounded, explicit checklist **before** touching the
   browser or sending the first request. This is the main lever for token efficiency — if the
   request is combinatorially large (every field × every panel × both modes), state the resulting
   checklist size and structure back to the user before grinding through it, rather than silently
   grinding through it.
2. **Choose the account, authenticate, and confirm its state** — see
   `references/accounts-and-credentials.md`. State the persona and what was confirmed about it in
   the header block; a run that doesn't say which account produced a finding is not reproducible.
3. **Happy path first.** Walk the checklist's core flow end-to-end exactly as a normal caller
   would — real clicks/typing/navigation in UI mode, real requests in API mode. Confirm it before
   doing anything adversarial.
4. **Then dig into edge cases, deliberately trying to break it** — use
   `references/bug-shapes.md` as a generator.
5. **Attribute before you score — run the control.** When the thing under test is a flag, a
   toggle, or a setting, re-run the same scenario with it **off** before scoring anything. The
   delta between the two runs *is* the finding; whatever is common to both belongs to the base,
   not to the change under test. No way to turn it off → say so, and report every finding as
   unattributed rather than pinning it on the change.
6. **Report each confirmed bug as soon as it's found**, scored per the model below — don't batch
   everything to the end.
7. **For `[CRITICAL]`/`[HIGH]` bugs, write the regression test** — see
   `references/regression-artifact.md`. `[MEDIUM]`/`[LOW]` are reported but not auto-spec'd unless
   asked.
8. **Offer to file eligible findings** — see `references/filing-findings.md`. Draft each one,
   show it, and create only on a yes.
9. **If the target exposes a version signal** — a commit SHA, a build banner, a version field —
   note it at the start and re-check it at the end; if it changed mid-run, say so and mark which
   findings predate the change. No such signal → skip this step, don't invent one.
10. **Clean up.** Remove everything created during the run — see the cleanup notes in
    `references/api-mode.md` for the API side. If you switched branches or checked something out
    locally for this run, offer to switch back — offer, don't just do it. Then close with the
    summary table.

**Stop condition.** The checklist is the budget. When it's exhausted — or a reasonable budget of
edge cases per item is spent — stop and report. Do not wander. If the remaining surface seems
worth more time, say so and let the user decide.

## Bug shapes — use these as the generator

Don't wait to be told what to try. The full catalogue — COPY, NAMES, PERSIST, LISTS, STALE, ASYNC,
SILENT, ENTITLEMENT, and the API-mode additions (SPEC, STATUS, AUTHZ, TYPES, PAGINATION, RATE) —
is in `references/bug-shapes.md`. Read it before the adversarial pass (workflow step 4).

## Regression artifact

A regression test is an *output artifact*, written only after a bug has been confirmed by hand —
never a substitute for actually exercising the app. Full rules for finding the right harness and
verifying the test actually runs are in `references/regression-artifact.md`.

## Token efficiency

- The upfront checklist is the main budget control — use it to avoid open-ended wandering.
- Screenshot only at decision points or as bug evidence, not after every single action.
- Batch same-page checks into one navigation instead of re-navigating per assertion.
- For repetitive sweeps (e.g. "test every field type"), report terse one-line pass confirmations
  per item and only expand detail where something actually failed.

## Reporting

### Bugs

For each confirmed bug:

- Severity label: `[CRITICAL]` / `[HIGH]` / `[MEDIUM]` / `[LOW]`
- The mode that produced it — UI or API — since a run may use both
- BUG_SCORE + factor breakdown, and any floor that was applied
- The oracle the expectation came from
- The account it was found under, and what was confirmed about its state
- The control run: does it still reproduce with the feature off? Unattributed findings say so
- Steps to reproduce
- Expected vs. actual

Anything without an oracle is reported as `[OBSERVATION]` and is **not** scored.

### Summary table

| Feature | Status | Notes |
|---|---|---|

## Filing findings

Confirmed findings can be filed somewhere the team will see them. Never file without showing the
draft and getting a yes. Full workflow — asking where, if anywhere, matching the target
workspace's own conventions, the eligibility table, and the duplicate-check discipline — is in
`references/filing-findings.md`.

## Bug prioritization model

```
BUG_SCORE = IMPACT × REPRODUCIBILITY × SURFACE          (1–75)
Severity  = the higher of (score tier, floor tier)
```

- **IMPACT** (1–5): functional severity
- **REPRODUCIBILITY** (1–5): how reliably it reproduces
- **SURFACE** (1–3): how many users it reaches

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
| REGRESSION — a previously working feature broken | at least `[MEDIUM]` |
| SECURITY **and** DATA_LOSS together | `[CRITICAL]` |

Reporting and scoring must always agree: state the score, the factors, and any floor applied.

## Examples

**No target, no oracle given** — both are asked for before anything else:

> *beta test the checkout flow*

```
Two things before I start: what URL is this running at, and what's the source of truth for
how checkout should behave — a PR, a spec, a ticket, or your own description of the expected
flow?
```

**Target and oracle both given, UI mode inferred:**

> *beta test https://app.example.com/checkout against https://github.com/acme/shop/pull/482*

```
Target    https://app.example.com/checkout
Mode      UI — a page was named
Oracle    PR #482 — "Add saved-card checkout"
Account   asking which configured persona to test as...

Checklist — 5 items: happy-path checkout with a saved card · add a new card
mid-checkout · remove the only saved card · expired card at submit · empty
cart. Starting the happy path.
```

**API mode, inferred from the endpoint, `bruno-mcp` authoring a collection on the fly:**

> */beta-tester QA POST /v1/orders on https://api.example.com against the OpenAPI spec*

```
Target    https://api.example.com/v1/orders
Mode      API — an endpoint was named. Browser not required, not attached, not a problem.
Client    bruno-mcp available → authoring a collection (none existed for this target)
Account   DEFAULT · token verified once ✓
Oracle    the project's openapi.json, operation POST /v1/orders

Checklist — 6 items: happy-path create · documented-vs-accepted parameter
sweep · omit each mandatory field · malformed body · wrong persona's token ·
error-payload shape check. Everything created is cancelled before the summary.
```
