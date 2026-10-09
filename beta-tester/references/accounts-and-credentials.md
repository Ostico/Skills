# Accounts and credentials

## Where credentials live

With the project under test, in its git directory, mode `0600`. The path is resolved from the
current directory — the project's checkout — never hardcoded. The first rule that applies wins:

```
$BETA_TESTER_ENV                  an override; if set it must exist
<git common dir>/beta-tester.env  inside a git repo: .git/beta-tester.env
$HOME/.beta-tester.env            only outside any git repo
```

Every rule that applies is final: a file missing where it points is an error, never a reason to
try the next one. Inside a git repo, a file in `$HOME` is not consulted — the accounts belong to
this project, and another project's `ADMIN` is not this one's.

**Why `.git`.** Accounts are per project, and the git directory is the one place in a project
that is never versioned:

- git never tracks anything inside it, so no `add -f`, ignore rule or rename can commit or push
  the file;
- it survives what wipes the working tree — a branch switch, `git stash -u`, `git clean -fdx`;
- every linked worktree resolves to the same main `.git` (`git rev-parse --git-common-dir`), so
  one file serves them all.

A fresh clone doesn't have it, and copying the whole project directory copies it. Create it once
per clone:

```bash
f="$(git rev-parse --git-common-dir)/beta-tester.env"
cp "<skill dir>/assets/credentials.env.example" "$f" && chmod 0600 "$f"
```

Then fill in real values there.

**Check once per project that `.git` stays private.** Neither Apache nor nginx refuses it by
default, and mode `0600` doesn't stop a process running as you:

- **A web server whose document root is the checkout** must deny `.git` — matecat's root
  `.htaccess` does, with `RedirectMatch 404 ^/\.git`. A dev server started in the checkout
  (`php -S`, `python -m http.server`) serves it to anyone who asks.
- **A container image built from the checkout** must exclude it: `.git` in `.dockerignore`, or
  `COPY . .` ships the file. An rsync deploy of the whole directory does the same.
- **A container with the checkout bind-mounted** can read it, as it can read the rest of the tree.

A project that fails one of these → keep the file outside it, and point `$BETA_TESTER_ENV` at it.

**Run from the target's checkout.** The path comes from the current directory, so a command run
anywhere else reads another project's accounts, or none. When the target's source isn't checked
out on this machine, set `$BETA_TESTER_ENV`. Name the resolved file — `$BETA_ENV_FILE`, a path,
never a value — once, when you pick the persona at workflow step 2.

## The helper — source it in every command

`scripts/beta-env.sh`, in this skill's directory, does the resolving and checking, and is the
only way this skill reads the file. **Shell state does not survive between tool calls**, so
source it at the start of every command that touches a credential:

```bash
. "<skill dir>/scripts/beta-env.sh" || exit 1
```

Sourcing it:

- resolves the path as above;
- refuses a missing file, and a file that grants any permission to group or others — the mode of
  a symlink's target is what counts, and a stricter mode such as `0400` passes;
- defines `beta_personas`, which prints each usable persona and what it can drive (`UI`, `API`),
  plus `TYPED` when the user allows typed login for it;
- defines `beta_has KEY`, which prints nothing and only succeeds when the key is set;
- defines `beta_val KEY`, which prints that key's value and fails when it is not set.

"Set" means not blank, not whitespace only, and not a leftover placeholder. Trailing whitespace,
a CRLF file's `\r` included, is dropped from every value. To check that a credential exists, use
`beta_has`, never `beta_val`: the second prints it.

It parses the file and never sources it, so nothing written in the credentials file ever runs.
A refusal is `[BLOCKED]`: stop and give the user the fix it printed.

## What may be shown, and the one exception

`_PASSWORD` and `_API_TOKEN` values are **secrets**. They never go into a report, a summary, a
filed task, a file inside a repo, or a command string. Never `cat` the file, never `set -x`.

`_EMAIL` values are identifiers, not secrets. Showing one in the chat is fine — the login check
below needs it. In a report or a filed task, name the persona key instead, since the people
reading it don't need the test account's address.

**The one exception.** A secret has to reach you before you can type it into a login form or
pass it to an MCP tool such as `bruno-mcp`. Get it with `beta_val KEY` in a tool call of its own,
one value per call, immediately before the call that uses it. That output, and the call that
uses it, put the value in the session transcript. No instruction prevents that, which is why
these must be test accounts — never a personal account or a production administrator. Nowhere
else may the value appear.

The exception needs permission for the persona: either `beta_personas` shows `TYPED` on its line
(the user set `BETA_TESTER_<PERSONA>_TYPED_LOGIN=allow`, a standing yes), or the user said yes to
it in this run. See "How the browser gets logged in". Without either, a secret never reaches you:
the browser logs in another way, and API calls go through direct HTTP.

When the secret goes to a shell command instead — `curl`, say — it never needs to reach you. Read
it with `beta_val` inside that same command and pass it through stdin (see "Secret hygiene in
flight" in `api-mode.md`).

## Schema

```
BETA_TESTER_<PERSONA>_EMAIL
BETA_TESTER_<PERSONA>_PASSWORD
BETA_TESTER_<PERSONA>_API_TOKEN     # optional — its presence is what enables token-based API calls
BETA_TESTER_<PERSONA>_LABEL         # optional, one line, shown in the picker
BETA_TESTER_<PERSONA>_TYPED_LOGIN   # optional, `allow` — the skill may handle this persona's
                                    # password and token itself, without asking each run
```

`<PERSONA>` is a free identifier — `DEFAULT`, `ADMIN`, `TRIAL`, `PAID`, whatever the account is
for in this project.

Real-world auth shapes vary — a bearer token, a custom header pair, a query parameter, Basic auth.
`_API_TOKEN` holds whatever single credential the target issues; **the skill asks once, before the
first API-mode request of the run, how that token is actually sent**, and remembers the answer for
the rest of the run rather than assuming a shape that isn't documented. Don't try to encode the
transport into the env file — the target's own docs or the oracle usually say it, and asking once
is cheap.

**Personas are discovered by scanning key names** (`beta_personas`), never from a separate list
variable — that would just be a second place to forget. Each line it prints is a persona and
what it can drive: `UI` when `_EMAIL` and `_PASSWORD` are both set, `API` when `_API_TOKEN` is —
`DEFAULT UI API`, `ADMIN UI`. A persona may be UI-only, API-only, or both. `TYPED` follows when
the persona is `UI` or `API` and `_TYPED_LOGIN` is `allow` — `OTHER UI API TYPED`. It reads the
values without printing any of them.

**An empty or placeholder value is not a configured persona.** `=`, `=""` and `=''` are values
someone hasn't filled in yet, and so are the placeholders older copies of the example file
shipped (`change-me`, an `@example.com` address), and so is a value of only whitespace. The helper treats
all of them as not set, for every key, so the picker never offers an account that is certain to
fail. That is all it can promise: a filled-in credential can still be wrong, and the login or the
first authenticated call is where that shows.

## Choosing one — always ask

Asked once the checklist exists (workflow step 2 in `SKILL.md`), because only the checklist says
whether a second persona is needed. Never infer the account from the oracle or from the surface
under test. A card or issue names whoever reported or requested it, which is not necessarily the
account that carries the relevant entitlement.

- Ask with one question, one option per persona configured, labelled with `_LABEL` where it
  exists, and annotated with what `beta_personas` says it can drive. Beyond a handful of
  options, list the personas as text and ask in prose.
- **Offer only personas that carry the credential the run will use.** Token-based API calls need
  `API`; a login — in the browser, or over HTTP against session-backed endpoints (see
  `api-mode.md`) — needs `UI`. Listing a persona that can't act just produces a dead end two steps
  later.
- **A cross-persona shape needs a second persona** — AUTHZ, TAMPER, or ENTITLEMENT on the
  checklist (see `bug-shapes.md`). Ask for it in the same question. For AUTHZ and TAMPER it plays
  the other caller, so ideally it has no relation to the first: a different team, a different
  organisation. For ENTITLEMENT it is the account without the gated feature. Only one persona
  configured → those items are `NOT RUN`; say so.
- Exactly one persona configured, and no second one needed → state it and skip the question.
- The request already names the account (*"...as the admin account"*) → skip the question, state
  the choice.
- **None configured for what the run needs** → say so, and point at
  `assets/credentials.env.example` and the resolved file path. Offer the two ways forward: the
  user adds the credentials to the file and says go, or — UI mode only — the run tests as the
  account the browser is already signed in as, recorded as that persona and checked like any
  other (see below). Never ask for a password or token in the chat: that is exactly what the file
  exists to avoid.

Do **not** try to mint a new credential mid-run on the target's behalf unless the task explicitly
asks for that — creating accounts or tokens is itself an action with consequences, not a setup
step to take silently.

## Logging in, and proving it took (UI mode)

A browser shares the user's real session, so it may already be signed in as someone else
entirely. Never assume. (Token-based API calls log nobody in — they authenticate per request and
never touch the browser's session. See `api-mode.md`.) The cleanest set-up is a separate browser
profile kept for testing, so a run never touches the user's own sessions; suggest it once if the
run would otherwise have to log the user out.

1. Load the app and read the signed-in identity off the page. Compare it with the persona's
   `_EMAIL`.
2. On a mismatch, **ask before logging anyone out** — unless this persona's credentials have
   already been used successfully in this session. A failed login *after* a logout ends the
   user's working session for nothing. State which account is signed in and which persona was
   chosen, and let them choose; testing as the account already signed in is often the right
   answer, provided it's recorded as the persona. On a yes, log out **through the UI**, then log
   in the way chosen at workflow step 2 (see "How the browser gets logged in", below). Don't
   clear cookies blind — a half-cleared session produces phantom logouts that look
   exactly like bugs you're about to file.
3. **Prove the account is actually in the state you need.** How to check this is project-specific
   — a role badge or plan indicator on a settings page, a field in a response the app already
   makes, a visibly different set of controls. Find the project's own way of showing this rather
   than assuming one; if there's no obvious way, ask. **It doesn't check out → stop** and report
   `[BLOCKED]`. That account doesn't have what you need to test, so proceeding tests core
   behaviour wearing the wrong label. It is not scored and never filed.

**Single sign-on, OAuth, and second factors** can't be driven from this file — there is no
password to type, or there is a code only the user's device receives. Use the session already
signed in (after step 3), or ask the user to complete the login by hand and say when it's done.
Never drive a third-party sign-in on your own: in the user's browser it acts as their real
identity.

## How the browser gets logged in

Three ways, in this order of preference. Only the third puts a password in the session
transcript.

1. **The account already signed in.** Read the identity off the page and record it as the
   persona. Nothing is typed.
2. **The user logs in by hand.** Ask: *"Log in as `<persona>` (`<email>`) and tell me when you're
   done."* The password never reaches you. It costs the user one action per switch, and needs
   someone there to do it.
3. **You type the password** — `beta_val` in a call of its own, then the browser tool. Only for a
   persona with permission (see "The one exception"). If the browser tool refuses to type into a
   password field, fall back to 2.

**Decide once, at workflow step 2, not at every switch:**

1. Order the checklist by persona — all of A's items, then all of B's — so each persona is
   entered once.
2. Give the second persona API mode wherever the item doesn't depend on what *that persona sees*
   in the UI (see "The second persona acts through the API"). Those items need no browser switch.
3. Count the browser logins left. **Every login counts**, the first one included: the browser
   signed in as someone other than the persona needs a login too. Only a browser already signed
   in as the persona needs none. Read the signed-in identity off the page before asking, and
   count against the personas you propose. If the user picks others, recount; a method question
   that only becomes necessary then follows the persona answer, still asked once.
   - **none** → way 1; no question about the method.
   - **one, for a persona without `TYPED`, and someone there** → way 2; no question about the
     method.
   - **one or more, and every persona involved shows `TYPED`** → way 3, without asking.
   - **otherwise, with someone there** → one question, in the same message as the persona question: *"This run needs
     N account switches between A and B in the browser. I can log in for you by typing the
     password from the credentials file — the value ends up in this session's transcript — or
     you switch account when I ask. Which do you prefer?"* The answer holds for the whole run.
   - **nobody there** (a background run) → way 3 for each persona that shows `TYPED`. A persona
     with no usable way — no `TYPED`, or the browser tool refuses to type into the password field
     — has its browser items `NOT RUN — no unattended login for <persona>`. A background run never
     logs out an account it didn't sign in itself: a first login that would log out someone else
     is `NOT RUN — signed in as someone else`, unless the user approved that logout before the run.
     The rest of the run continues.

A persona that signs in through single sign-on, OAuth, or a second factor has no password to
type, `TYPED` or not: way 1 or 2 only (see "Single sign-on, OAuth, and second factors" above).

State the way chosen on the header block's `Account` line.

### The second persona acts through the API

A browser holds one identity per site — its tabs share cookies — so every browser switch is a
logout and a login. Most cross-persona items don't need one:

- **TAMPER** → the browser stays as A. B creates the resource through API mode, and A tries to
  reach it from the browser.
- **AUTHZ** → both callers through API mode (see `api-mode.md`).
- **ENTITLEMENT** → what the gated persona *sees* is the test, so the browser must be that
  persona: a switch.

Over direct HTTP the secret goes from the file to `curl` through stdin and never reaches you (see
"Secret hygiene in flight" in `api-mode.md`), so this route needs no permission. The persona needs
`API` for a token, or `UI` for a session-backed login over HTTP.

## The frozen-entitlements trap

Some products snapshot a resource's configuration — plan, feature set, permissions — at the
moment it's created, rather than reading the owning account's *current* state each time. An
**existing resource can keep the entitlements it was created with, whoever opens it later.** If
you suspect this pattern applies here (it's common for projects, workspaces, and similar
container resources), create a **new** resource as the persona you're testing rather than reusing
one someone else made; reusing an existing one silently tests the account that originally created
it. If you're not sure whether the pattern applies, say so and test both ways if it's cheap to do.

## Switching mid-run

Every browser switch is three steps:

1. **Log out** through the app's own control, not by clearing cookies.
2. **Log in** as the next persona, the way chosen at workflow step 2.
3. **Prove who is signed in now** — steps 1 and 3 of "Logging in, and proving it took". A login
   that silently failed runs B's items as A, and every result after it is false.

Announce each switch in the output, and tag every finding with the persona it was found under. A
run that doesn't say which account produced a finding is not reproducible.

## What is not in the credentials file, and cannot be

A resource's own capability — a project password, a session token, an access link — belongs to a
resource, not to an account, so it is never configured ahead of time: never look for one in the
env file. Normally the run creates the resource, reads the capability out of the response, and
uses it from there.

The exception is an oracle that names a specific existing resource — a bug report that links the
project it broke on. Then that resource *is* the test, and asking the user for its link is fine.
Keep the frozen-entitlements trap above in mind: it carries its creator's configuration.
