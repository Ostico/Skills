# Accounts and credentials

## Where credentials live

Outside every repo, mode `0600`, never committed. Resolve the path — never hardcode it:

```
$BETA_TESTER_ENV        an override; if set it must exist
$HOME/.beta-tester.env  the default
```

`$BETA_TESTER_ENV`, when set, is an override and is never silently skipped — if it points at
nothing, that is an error, not a fallthrough.

**A path inside the project's own repo is never consulted, deliberately.** A repo is often
writable by the running application, may get `git clean`ed, and a skill file that ships inside a
repo can be checked out onto a branch that overwrites it. Keep real values outside every repo the
skill might ever touch. Copy the schema from `assets/credentials.env.example`, next to this file,
into the resolved path and fill in real values there.

**Check the permissions before reading it.** Group- or world-readable → stop, and give the fix:

```bash
[ "$(stat -c '%a' "$ENV_FILE")" = "600" ] || echo "run: chmod 0600 $ENV_FILE"
```

**Values are never printed.** `_EMAIL`, `_PASSWORD`, and `_API_TOKEN` go into a shell variable and
are used from there — never `cat`, never `echo`, never inlined into a command string, never
`set -x`, and never into a report, a summary table, or a filed task. Persona keys and `_LABEL`
values may be shown; that is what the picker is made of.

## Schema

```
BETA_TESTER_<PERSONA>_EMAIL
BETA_TESTER_<PERSONA>_PASSWORD
BETA_TESTER_<PERSONA>_API_TOKEN     # optional — its presence is what enables API mode
BETA_TESTER_<PERSONA>_LABEL         # optional, one line, shown in the picker
```

`<PERSONA>` is a free identifier — `DEFAULT`, `ADMIN`, `TRIAL`, `PAID`, whatever the account is
for in this project.

Real-world auth shapes vary — a bearer token, a custom header pair, a query parameter, Basic auth.
`_API_TOKEN` holds whatever single credential the target issues; **the skill asks once, at the
start of the first API-mode run, how that token is actually sent**, and remembers the answer for
the rest of the run rather than assuming a shape that isn't documented. Don't try to encode the
transport into the env file — the target's own docs or the oracle usually say it, and asking once
is cheap.

Discover the personas by **scanning key names**, never from a separate list variable — that would
just be a second place to forget. Union `_EMAIL` and `_API_TOKEN`, so a persona may be UI-only,
API-only, or both:

```bash
grep -oE '^BETA_TESTER_[A-Z0-9_]+_(EMAIL|API_TOKEN)=("[^"]+"|[^"[:space:]]+)' "$ENV_FILE" \
  | sed -E 's/=.*$//; s/_(EMAIL|API_TOKEN)$//' | sort -u
```

**An empty value is not a configured persona.** `BETA_TESTER_DEFAULT_EMAIL=""` is a placeholder
someone hasn't filled in yet, and the regex above requires a non-empty value precisely so the
picker never offers an account that can't authenticate. Treat a persona whose *needed* credential
is blank as absent: in UI mode that's `_EMAIL`/`_PASSWORD`, in API mode `_API_TOKEN`. A persona can
legitimately be configured for one mode and blank for the other.

No credential configured for the persona you need → say so and point at
`assets/credentials.env.example`. Do **not** try to mint a new credential mid-run on the target's
behalf unless the task explicitly asks for that — creating accounts or tokens is itself an action
with consequences, not a setup step to take silently.

## Choosing one — always ask

Never infer the account from the oracle or from the surface under test. A card or issue names
whoever reported or requested it, which is not necessarily the account that carries the relevant
entitlement.

- Ask with one question, one option per persona configured, labelled with `_LABEL` where it
  exists, and annotated with what it can drive — `UI`, `API`, or both. Beyond a handful of
  options, list the personas as text and ask in prose.
- **In API mode, offer only personas that carry a non-empty `_API_TOKEN`.** A persona with a
  login and no token can't act in this mode, and listing it just produces a dead end two steps
  later. The same applies in reverse: an API-only persona is not offered in UI mode.
- Exactly one persona configured → state it and skip the question.
- The request already names the account (*"...as the admin account"*) → skip the question, state
  the choice.
- None configured → ask the user directly for credentials to use for this run, once, rather than
  falling back to whatever the browser happens to already be signed in as.

## Logging in, and proving it took (UI mode)

A browser shares the user's real session, so it may already be signed in as someone else
entirely. Never assume. (API mode logs nobody in — it authenticates per request and never touches
the browser's session. See `api-mode.md`.)

1. Load the app and read the signed-in identity off the page.
2. On a mismatch, **ask before logging anyone out** — unless this persona's credentials have
   already been used successfully in this session. A failed login *after* a logout ends the
   user's working session for nothing. State which account is signed in, which one is configured,
   and let them choose; testing as the account already signed in is often the right answer,
   provided it's recorded as the persona. On a yes, log out **through the UI**, then log in.
   Don't clear cookies blind — a half-cleared session produces phantom logouts that look exactly
   like bugs you're about to file.
3. **Prove the account is actually in the state you need.** How to check this is project-specific
   — a role badge or plan indicator on a settings page, a field in a response the app already
   makes, a visibly different set of controls. Find the project's own way of showing this rather
   than assuming one; if there's no obvious way, ask. **It doesn't check out → stop.** That
   account doesn't have what you need to test, so proceeding tests core behaviour wearing the
   wrong label. This is a setup problem, not a finding: it is not scored and never filed.

## The frozen-entitlements trap

Some products snapshot a resource's configuration — plan, feature set, permissions — at the
moment it's created, rather than reading the owning account's *current* state each time. An
**existing resource can keep the entitlements it was created with, whoever opens it later.** If
you suspect this pattern applies here (it's common for projects, workspaces, and similar
container resources), create a **new** resource as the persona you're testing rather than reusing
one someone else made; reusing an existing one silently tests the account that originally created
it. If you're not sure whether the pattern applies, say so and test both ways if it's cheap to do.

## Switching mid-run

Allowed, but announce it in the output and tag every subsequent finding with the persona it was
found under. A run that doesn't say which account produced a finding is not reproducible.

## What is not in the credentials file, and cannot be

A resource's own capability — a project password, a session token, an access link — is created
*by the run*, not configured ahead of time. Never look for one in the env file, never ask the user
for it. Create the resource, read the capability out of the response, and use it from there.
