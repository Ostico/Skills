# API mode

The API is a first-class target, not a debugging aid for the browser. An API-mode run gets the
same treatment as UI mode: oracle, bounded checklist, happy path, adversarial pass, control run,
severity score, regression test, offer to file.

## Authenticating

Send the credential however the target actually documents it — commonly an
`Authorization: Bearer <token>` header, a custom header (or header pair), or a query parameter.
**Ask once**, before the first API-mode request of the run, if the shape isn't already obvious
from the oracle or a published spec, then remember the answer for the rest of the run. Never guess
a shape that isn't documented — a wrong shape and a wrong credential fail identically, and
conflating them produces a false finding.

**Session-backed endpoints** — the kind a web UI's own front end calls, authenticated by a session
cookie and often a CSRF token — can be driven over HTTP too: send the login request, carry the
session cookie and token forward, and keep going. Use this when the endpoint under test accepts
no API token. The persona then needs `_EMAIL` and `_PASSWORD` rather than `_API_TOKEN`. A flow
with a second factor or a third-party sign-in still needs the browser (see
`accounts-and-credentials.md`).

## Verify the credential once — and only once

**Do not validate a token by its length or shape.** Real systems often have more than one
generation of key format still valid (a hardening change that lengthened new keys doesn't
invalidate old ones), and the server-side check is usually a plain lookup, not a shape check. A
shape check here would reject working credentials.

**Prefer the cheapest authenticated call available** — any endpoint that requires auth and costs
no rate-limit budget proves the credential. Call it **once per run and cache the result**; do not
re-verify on every request. The verification fails → `[BLOCKED]`, not a finding.

Base URL is the target given for this run. There is no default and nothing to fall back to if it
wasn't given — see "Fail fast, not pre-flight" in `SKILL.md`.

## Resource capabilities

A resource-scoped capability — a project id and password, a session token, an access link — is
created by the run, not configured. See "What is not in the credentials file" in
`accounts-and-credentials.md`.

## Proving entitlements without a page

UI mode reads account state off a rendered page. API mode usually has no page, but the target's
own response to creating a resource often carries the same information — plan, role, feature
flags, or similar — in its JSON body. If the target's API surfaces this:

1. Create a resource **as the chosen persona**.
2. Read the field back from the response.
3. The state you're testing must be reflected there. **It isn't → stop** and report `[BLOCKED]`,
   exactly as in UI mode: that's a setup problem, not a finding. It is not scored and never filed.

What this proves is the **resource's own** state rather than just the account's — which is
stronger evidence, not weaker, when the product snapshots configuration at creation time (see the
frozen-entitlements trap in `accounts-and-credentials.md`). It also means that trap applies with
full force here too: reading state off a resource somebody else created tells you about *their*
account, convincingly and wrongly.

## Choosing the client

**Choose per persona.** `bruno-mcp` needs credential values in its `variables`, which puts them
in the session transcript, so it acts as a persona only when that persona shows `TYPED` or the
user said yes this run (see "The one exception" in `accounts-and-credentials.md`). Every other
persona's authenticated requests go over direct HTTP, **without asking** — API mode never asks for
the in-run yes, because direct HTTP does the same job without exposing the value. Requests that
carry no credential may always use `bruno-mcp`. The header's `Client` line names the client per
persona.

**For the personas it may act as, probe for `bruno-mcp` first.** Where available, it authors and
runs requests in-process rather than needing a pre-existing collection or a hand-rolled `curl`
command:

1. `list_collections`, then `list_requests` — if a collection already exists for this target, it
   can be reused, with care. It was written for someone else's purpose: it may hold DELETE,
   payment, or email requests, and plaintext credentials in its environment files.
   - `read_request` every request you intend to run, before running it.
   - Run only the requests the checklist needs, never the whole collection by default:
     `run_collection`'s `requests` lists request files or directories (a directory expands to
     every request under it). With `groups`, every group carries its own `requests` — a group
     that omits it runs the whole collection.
   - The irreversible-action gate in `SKILL.md` applies to each request in it, as to any other.
   - Never print its environment's values.
2. Otherwise **author one on the fly**, outside the project's repo unless the user asks otherwise,
   so test files don't end up in a commit:
   - `create_collection`
   - `create_environment` — the base URL as a plain variable; each credential **declared**
     `secret: true`, which stores its name and never its value. A credential written as a plain
     variable lands in the environment file on disk.
   - `write_request` for each checklist item, referencing variables — never a credential or base
     URL hardcoded into the request — with inline assertions via `add_test_script` where the
     response shape can be checked mechanically (status code, a required field present, a value
     matching what was sent).
   - `read_request` to verify what was actually written **before** running it — this is the step
     that catches an authoring mistake (a wrong header, a missing body field) before it produces a
     misleading result rather than after.
   - `run_collection` to execute. Pass credential values through its `variables`, which are held
     in memory and never written to disk. Each value reaches you through the one exception in
     `accounts-and-credentials.md`: `beta_val KEY` in a call of its own, right before this one —
     so it needs that persona's permission (`TYPED`, or a yes in this run). Without it, send that
     persona's authenticated requests over direct HTTP, where the value never reaches you.
3. **Every caller is its own group.** More than one persona with permission in a run
   (authorization probes) → one entry in `groups` per caller; a caller without permission runs
   over direct HTTP instead. Each group has its own `variables`, its own variable store, and
   its own cookie jar, so nothing leaks from one caller to another — in either direction:
   - **Give every group an explicit `requests` list.** A group without one runs the whole
     collection. Top-level `requests` cannot be combined with `groups`.
   - **Pass ids across callers in a second call.** A resource persona A creates is invisible to
     B's group in the same call. Create it in a first call, get its id back with
     `captureVariables` (the request's script must `bru.setVar` it), and pass it into B's group
     `variables` in the next call.
   - **Check that the URL resolved before counting a refusal.** A request that went out with a
     literal `{{...}}` in its URL hit nothing, and its 404 or 400 is not a refusal. Read the URL
     each result reports.
4. **Know what the cookie jar adds.** `cookieJar` is a `run_collection` option, on by default: it
   keeps every response's cookies and adds them to later requests in the same group. A request
   that sets its own `Cookie` header wins over the jar, but the jar still adds every cookie the
   request did *not* set — so a request that omits a credential can still go out carrying one
   from an earlier login, and pass as an authentication bypass that isn't one. Arrange the groups
   so that can't happen:
   - **a session-backed caller** → its own group, jar **on**: the login request first, then the
     probes that act as that caller.
   - **the no-credential probe** → a group of its own that never logs in, so its jar is empty.
   - **token-only probes** → a `run_collection` call of their own with `cookieJar: false`, so only
     the declared credential goes out. `cookieJar` applies to the whole call, not to one group, so
     these can never share a call with a session-backed caller.
5. **Loopback and private targets** are refused with `SSRF blocked` and status 0 unless the
   server's operator allowlisted them (`BRUNO_SSRF_ALLOWLIST`). That is the client's limit, not
   the target's: don't report the target as down. Ask the user to allowlist it, or fall back to
   direct HTTP and say so.
6. **No `bruno-mcp` tools in this session → fall back to direct HTTP calls, and say so explicitly
   in the header block.** A run that silently picks a path is a run nobody can reproduce.

## Secret hygiene in flight

On top of the output rule in `accounts-and-credentials.md`:

- **Direct HTTP**: source the helper in the same command, read the credential with `beta_val`,
  and pass it through stdin, so it never appears in the command string or the process list
  (`curl` 7.55 or newer). The base URL is the run's target, written out in the command. A token
  in a header:

  ```bash
  . "<skill dir>/scripts/beta-env.sh" || exit 1
  TOKEN=$(beta_val BETA_TESTER_DEFAULT_API_TOKEN) || exit 1
  printf 'Authorization: Bearer %s\n' "$TOKEN" | curl -sS -H @- "https://api.example.com/v1/orders"
  ```

  A session-backed login: the body from stdin, built with `jq` so a quote in the password can't
  break it, and the session cookie in a temporary file outside any repo. `jq` reads the
  credentials from its environment, which only the same user can read; `--arg` would put them in
  its argv, which any user can list with `ps`:

  ```bash
  . "<skill dir>/scripts/beta-env.sh" || exit 1
  EMAIL=$(beta_val BETA_TESTER_DEFAULT_EMAIL) && PASS=$(beta_val BETA_TESTER_DEFAULT_PASSWORD) || exit 1
  JAR=$(mktemp "${TMPDIR:-/tmp}/beta-jar.XXXXXX") && echo "cookie jar: $JAR"
  EMAIL="$EMAIL" PASS="$PASS" jq -n '{email: env.EMAIL, password: env.PASS}' \
    | curl -sS -c "$JAR" -H 'Content-Type: application/json' --data-binary @- "https://app.example.com/login"
  ```

  `$JAR` is gone in the next tool call, since shell state doesn't survive between calls. Later
  commands pass the literal path that line printed, to both options, so a session the server
  rotates is kept: `-b '<path>' -c '<path>'`. A target that wants a CSRF token on writes (see
  above) hands it out in the login response or a cookie in the jar; send it in the header the
  target names, read the same way. The summary step deletes the jar.

  Never inline a credential in a command string, and never `set -x`.
- `run_collection` masks credential values in the response headers it returns, but **not** in
  response bodies. Never echo a response body that reflects the credential back.
- **A credential minted during the run is a live capability.** Reproduction steps — in the report
  and in any filed task — name the endpoint and the *shape* of the input, never the actual value
  minted during the run.

## Rate limits

If the target rate-limits authentication or anything else, learn the actual window empirically
only if a finding truly depends on it — a couple of calls spaced out, not a tight loop — and don't
assume a round number like "per minute" without checking: real windows are often irregular.

**Learning a window means hitting the limit.** A login limiter can lock the persona's account for
the rest of the run, and a per-IP limiter can lock out everyone behind the same address. On a
target that isn't exclusively yours, that is a gated action (see `SKILL.md`): ask first.

## Cleaning up

API mode creates resources far faster than clicking does, so the mess accumulates faster too.
Track every resource minted as you go, and remove it before the summary using whatever the
target's own API offers for that (delete, archive, cancel — whichever exists). This is mandatory
on a target shared with other people, where the prefix-and-clean-up courtesy from `SKILL.md`
applies just as it does in the browser. Anything with no removal path, or whose removal failed,
goes in the summary with its id and where it lives.

The run's own files go too: any curl cookie jar (`rm -f` the path printed when it was made), and
the collection and environment authored for this run (`delete_collection`). Keep the collection
only if the user asks to, and say where it is.

## The spec as oracle

If the target publishes a machine-readable spec — OpenAPI/Swagger, a GraphQL schema, or similar —
use it as an oracle for request/response shape, **in both directions**: a documented parameter the
code ignores is as much a finding as an undocumented one the code silently requires.

If more than one copy of the spec exists (a hand-maintained one and a generated one, for example),
**ask which is authoritative** rather than assuming — a generated copy that's actually served live
usually outranks a hand-maintained one that's drifted, but that's a project-specific fact, not a
rule to assume blind.
