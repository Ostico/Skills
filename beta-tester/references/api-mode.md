# API mode

The API is a first-class target, not a debugging aid for the browser. An API-mode run gets the
same treatment as UI mode: oracle, bounded checklist, happy path, adversarial pass, control run,
severity score, regression test, offer to file.

## Authenticating

Send the credential however the target actually documents it — commonly an
`Authorization: Bearer <token>` header, a custom header (or header pair), or a query parameter.
**Ask once**, at the start of the first API-mode call, if the shape isn't already obvious from the
oracle or a published spec, then remember the answer for the rest of the run. Never guess a shape
that isn't documented — a wrong shape and a wrong credential fail identically, and conflating them
produces a false finding.

A login flow that mints a session (cookies, CSRF tokens, multi-step handshakes) is normally
browser-only — a test that needs it needs UI mode, because an API credential typically can't mint
a browser session on its own.

## Verify the credential once — and only once

**Do not validate a token by its length or shape.** Real systems often have more than one
generation of key format still valid (a hardening change that lengthened new keys doesn't
invalidate old ones), and the server-side check is usually a plain lookup, not a shape check. A
shape check here would reject working credentials.

**Prefer the cheapest authenticated call available** — any endpoint that requires auth and costs
no rate-limit budget proves the credential. Call it **once per run and cache the result**; do not
re-verify on every request. If the target rate-limits authentication attempts, learn the actual
window empirically only if you truly need to (a couple of calls spaced out, not a tight loop) —
don't assume a round number like "per minute" without checking, since real windows are often
irregular.

Base URL is the target given for this run. There is no default and nothing to fall back to if it
wasn't given — see "Fail fast, not pre-flight" in `SKILL.md`.

## What is not configured ahead of time, and cannot be

A resource-scoped capability — a project id and password, a session token, an access link — is a
capability for a resource that doesn't exist until the run creates it. Never look for one in the
credentials file, never ask the user for it. Create the resource, read the capability out of the
response, then discover whatever it unlocks from there.

## Proving entitlements without a page

UI mode reads account state off a rendered page. API mode usually has no page, but the target's
own response to creating a resource often carries the same information — plan, role, feature
flags, or similar — in its JSON body. If the target's API surfaces this:

1. Create a resource **as the chosen persona**.
2. Read the field back from the response.
3. The state you're testing must be reflected there. **It isn't → stop**, exactly as in UI mode:
   that's a setup problem, not a finding. It is not scored and never filed.

What this proves is the **resource's own** state rather than just the account's — which is
stronger evidence, not weaker, when the product snapshots configuration at creation time (see the
frozen-entitlements trap in `accounts-and-credentials.md`). It also means that trap applies with
full force here too: reading state off a resource somebody else created tells you about *their*
account, convincingly and wrongly.

## Choosing the client

**Probe for `bruno-mcp` first.** Where available, it authors and runs requests in-process rather
than needing a pre-existing collection or a hand-rolled `curl` command:

1. `list_collections`, then `list_requests` — if a collection already exists for this target, use
   it.
2. Otherwise **author one on the fly**:
   - `create_collection`
   - `create_environment` — put the base URL and the credential in as environment variables;
     never hardcode either directly into a request.
   - `write_request` for each checklist item, with inline assertions via `add_test_script` where
     the response shape can be checked mechanically (status code, a required field present, a
     value matching what was sent).
   - `read_request` to verify what was actually written **before** running it — this is the step
     that catches an authoring mistake (a wrong header, a missing body field) before it produces a
     misleading result rather than after.
   - `run_collection` to execute — use separate execution groups when a check needs more than one
     persona in the same run (e.g. authorization probes).
3. **No `bruno-mcp` tools in this session → fall back to direct HTTP calls, and say so explicitly
   in the header block.** A run that silently picks a path is a run nobody can reproduce.

## Secret hygiene in flight

On top of "values are never printed" (see `accounts-and-credentials.md`):

- Source every request's credential from an environment variable inside the authored
  collection/environment, or from a shell variable if falling back to direct HTTP. Never inline a
  token in a command string, never `set -x`, never echo a response that reflects the credential
  back.
- **A credential minted during the run is a live capability.** Reproduction steps — in the report
  and in any filed task — name the endpoint and the *shape* of the input, never the actual value
  minted during the run.

## Cleaning up

API mode creates resources far faster than clicking does, so the mess accumulates faster too.
Track every resource minted as you go, and remove it before the summary using whatever the
target's own API offers for that (delete, archive, cancel — whichever exists). This is mandatory
on a target shared with other people, where the prefix-and-clean-up courtesy from `SKILL.md`
applies just as it does in the browser.

## The spec as oracle

If the target publishes a machine-readable spec — OpenAPI/Swagger, a GraphQL schema, or similar —
use it as an oracle for request/response shape, **in both directions**: a documented parameter the
code ignores is as much a finding as an undocumented one the code silently requires.

If more than one copy of the spec exists (a hand-maintained one and a generated one, for example),
**ask which is authoritative** rather than assuming — a generated copy that's actually served live
usually outranks a hand-maintained one that's drifted, but that's a project-specific fact, not a
rule to assume blind.
