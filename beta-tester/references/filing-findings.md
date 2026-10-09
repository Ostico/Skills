# Filing findings

Confirmed findings can be filed somewhere the team will see them. **Never file without showing
the draft and getting a yes** — a task on a shared board is visible to colleagues and costs
someone's attention. This gate is separate from the target: the skill never asks whether a
target is safe to test, but it always asks before an action other people will see.

## Ask where, if anywhere

Ask once per run, at intake (see `SKILL.md`), whether the user wants confirmed findings filed,
and where. There's no fixed destination — Asana, a GitHub issue, Notion, Jira, Linear, or nowhere
are all legitimate answers. If the oracle itself came from a platform (a PR, a tracker card),
offer that as the default suggestion, but still ask; don't assume the user wants findings routed
to wherever the oracle happened to live.

- A connector for the named platform exists in this session → use it.
- No connector for the named platform → say so in one line, and offer to draft the finding as
  text the user can paste in themselves instead.
- The user says nowhere → report-only; skip this section entirely for the rest of the run.

## Learn the workspace's own conventions

This skill has no way to know a workspace's project ids, board sections, or custom field ids
ahead of time — those are per-workspace and change over time. Instead of hardcoding any of that,
**read a couple of existing tasks/issues** in the target project/board (if the platform's
connector supports listing or searching) to learn: where new, unreviewed items land, what fields
are commonly set, and the house style for a title and a description. Match that shape rather than
inventing one.

If nothing can be sampled (an empty board, a search tool that isn't available), draft a plain
task with the shape below and say that the workspace's own conventions couldn't be confirmed.

## What may be filed

| label | action |
|---|---|
| `[CRITICAL]` `[HIGH]` `[MEDIUM]` | eligible — draft a task, ask, file on yes |
| `[LOW]` | report only; file only if the user asks for it by name |
| `[OBSERVATION]` | **never** — it has no oracle, so there is nothing to assert |
| `[BLOCKED]` | **never** — the run couldn't reach or use the target, so it can't blame the product |

**Never file a finding whose cause turned out to be environmental** — misconfigured credentials, a
target that wasn't running the code under test, a client that refused the request. Re-label it
`[BLOCKED]`. Filing one sends a colleague hunting a defect that doesn't exist.

**Group copy/style-contract findings.** A thorough sweep against the project's own style
convention often finds several small ones at once. File **one** task with a checklist of the
strings, never one task per string.

## Security findings: private channel only

Anything that took the **SECURITY floor** is a vulnerability until fixed. A public issue, or a
board that people outside the project can read, publishes it.

- **Never** file it as a public issue or on a board readable outside the project.
- Offer the private routes the project has: a private security advisory on its forge (GitHub's
  draft security advisory, for example), the security contact in a `SECURITY.md`, or a tracker
  project the user confirms is restricted to the team.
- No private route is known → keep it in the report only, and say why it wasn't filed.
- The draft gives the minimum needed to reproduce. Never a working exploit beyond that, and never
  a live credential.

## Check for a duplicate first

Search the target project/board (if a search tool exists) on the symptom, the page or endpoint,
and the file path if you know it, before drafting.

- **The oracle itself already describes this symptom** → it isn't a new finding. Say so and file
  nothing; it's already where it belongs.
- **Match found** → don't create a second task. Offer to add a comment confirming it still
  reproduces, naming the target and any version signal available. Ask first; a comment notifies
  followers. A **security** finding never goes into a comment on an item people outside the
  project can read — a comment publishes it as surely as a new issue would. Use the private route
  above.
- **No match** → draft a new task.

## Task shape

Title — no severity prefix, the field or the body carries it:

```
Support link renders as a literal string, not interpolated (Header.tsx:42)
```

Body:

```
Severity     MEDIUM — score 20 (IMPACT 2 × REPRODUCIBILITY 5 × SURFACE 2), no floor applied
Oracle       [what grounded the expectation]
Target       [URL] · [UI/API] mode · account [persona] · [a commit SHA or build/version
             identifier, only if the target exposed one]
Control      [what the control run showed, or "none available: unattributed"]
Found while  [what the run was testing, and a link to the oracle if it had one]

Steps to reproduce
  1. ...

Expected     ...
Actual       ...

Evidence
  [screenshot description / response body / console output]
```

Always state the score with its factors and any floor, the oracle, the target and mode plus a
version signal when one exists, the control result, and the account with what was confirmed about
its state — a finding whose environment is unrecorded can't be re-checked later, and one found
under a particular persona may reproduce nowhere else.

**Never put a live credential in a filed task** — in its text or in an attached screenshot. No
token, no password, no minted session id or access link — a board item is visible to the whole team and outlives the run. Describe the input
by shape and name the endpoint or page; whoever picks the bug up will mint their own.

Report the created item's URL back.
