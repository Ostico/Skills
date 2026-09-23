# Bug shapes — use these as the generator

Don't wait to be told what to try. These are recurring bug clusters across web applications, not
a checklist to run mechanically — use them to generate adversarial cases against whatever the
oracle actually describes. COPY, NAMES, PERSIST, LISTS, STALE, ASYNC, SILENT, and ENTITLEMENT
apply in both modes; the six API-mode additions are below.

- **COPY** — user-facing text should follow the project's *own* stated convention, if it has one
  (a style guide, a `CLAUDE.md`, an existing consistent pattern in the UI). A string that breaks
  that project's own established convention is a real finding — inconsistency with the project's
  own rule, not a universal casing or wording law. Watch for CSS that transforms text (e.g.
  `text-transform`) and makes a string *look* consistent while the underlying value is wrong, and
  remember that exception/error messages are usually user-facing too, wherever they get surfaced
  in the response.
- **NAMES** — user-typed names are the sharpest input surface: unusual Unicode (astral/4-byte
  characters, combining marks, right-to-left text), HTML entity text, length limits,
  leading/trailing whitespace. Behaviour should be a clean refusal or a clean strip, never a
  silent truncation.
- **PERSIST** — omit an optional field on an update. Is existing data preserved, or silently
  wiped? Re-read the entity after saving; don't trust a success toast or a 200 status alone.
- **LISTS** — submit one malformed item inside a list (a row, a column, a batch entry). Does the
  whole save abort, or is that item skipped and logged cleanly? Either can be correct — but the
  behaviour should be deliberate, not incidental.
- **STALE** — read a value straight after writing it, in the same flow. Was a cache evicted
  properly, or is a pre-commit value served back? Reload; open the same data from a second
  surface (a different page, a different endpoint) and compare.
- **ASYNC** — anything queued to a background worker (an analysis job, a notification, a
  long-running import). Does the UI or API surface a failure, or does it silently keep looking
  fine while the job dies?
- **SILENT** — check the browser console and network tab on every page for JS errors and failed
  requests the UI never surfaced. **Arm the trackers first, then reload, then read.** Console and
  network capture usually only begin once you first call the tool that starts them, so a page that
  loaded before you armed it answers "nothing found" — indistinguishable from a clean pass, and
  the easiest false green in this whole exercise. Discount noise that's clearly an artifact of
  your own local setup (a hostname alias only your machine can't resolve, a browser extension) —
  but say explicitly what you discounted and why, rather than silently excluding it.
- **ENTITLEMENT** — when the product gates behaviour by plan, role, or feature flag: did the gate
  actually apply? Test under an account that has it and one that doesn't, and check the inverse
  too — a core-path change can be overridden by a gated path nobody exercises under the plain
  account, so a change that looks core-only still needs a pass under the gated persona.
- Plus the generic pass: empty/boundary/malformed input, rapid double-submits,
  permission-mismatched roles, expired/invalid sessions — respecting the shared-target courtesy
  from `SKILL.md` when the target is shared.

## API mode adds

- **SPEC** — request and response shape against whatever spec the target publishes, **in both
  directions**. A documented parameter the code ignores is as much a finding as an undocumented
  one it requires. Send every documented-optional parameter and check it had an effect; omit each
  one and check the call still succeeds.
- **STATUS** — does a failure carry the right HTTP status, or does everything collapse into 500?
  A wrong status usually points at a wrong exception/error type server-side, which is a real and
  locatable bug even without reading the server's code.
- **AUTHZ** — the sharpest surface in this mode. Many APIs resolve a resource's own access
  password/token separately from the caller's login, inside the handler rather than at the
  routing layer. Probe the seam: omit the credential entirely; send persona A's credential against
  persona B's resource; send a valid credential with a wrong resource-scoped secret; send a valid
  resource-scoped secret with no credential. Anything that authorises on the resource-scoped
  secret alone, with no check on who's calling, is an IDOR and takes the **SECURITY floor**.
- **TYPES** — numeric or boolean fields arriving as JSON strings, or vice versa. The finding is
  usually *inconsistency* — the same logical field typed one way in one response and another way
  in a sibling endpoint or a different API version — not the mere presence of a string.
- **PAGINATION** — don't just read a "next page" field, **call it**. A broken next-page link is
  invisible to anyone who only reads the field.
- **RATE** — don't assume a limiter's window is a round number ("N per minute") unless it's
  documented as such; if the actual window matters to a finding, learn it empirically rather than
  guessing. Needs the same shared-target courtesy as any other disruptive probe when the target
  isn't exclusively yours.
