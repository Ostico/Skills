# Filing findings

Confirmed findings can be filed somewhere the team will see them. **Never file without showing
the draft and getting a yes** — a task on a shared board is visible to colleagues and costs
someone's attention, the same reasoning behind every other confirmation gate this skill still
keeps despite dropping the production/staging gates (see "Fail fast, not pre-flight" in
`SKILL.md` — that one is about not pre-verifying the target, not about skipping confirmation on
actions visible to other people).

## Ask where, if anywhere

Ask once, per run, whether the user wants confirmed findings filed, and where. There's no fixed
destination — Asana, a GitHub issue, Notion, Jira, Linear, or nowhere are all legitimate answers.
If the oracle itself came from a platform (a PR, a tracker card), offer that as the default
suggestion, but still ask; don't assume the user wants findings routed to wherever the oracle
happened to live.

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

| severity | action |
|---|---|
| `[CRITICAL]` `[HIGH]` `[MEDIUM]` | eligible — draft a task, ask, file on yes |
| `[LOW]` | report only; file only if the user asks for it by name |
| `[OBSERVATION]` | **never** — it has no oracle, so there is nothing to assert |

**Never file a finding whose cause turned out to be environmental** — this skill has no
pre-flight to catch those before they happen, but a run that never managed to reach the target at
all, or whose credentials were misconfigured, isn't in a position to blame the product for what
it saw. Filing one sends a colleague hunting a defect that doesn't exist.

**Group copy/style-contract findings.** A thorough sweep against the project's own style
convention often finds several small ones at once. File **one** task with a checklist of the
strings, never one task per string.

## Check for a duplicate first

Search the target project/board (if a search tool exists) on the file path or symptom before
drafting.

- **The oracle itself already describes this symptom** → it isn't a new finding. Say so and file
  nothing; it's already where it belongs.
- **Match found** → don't create a second task. Offer to add a comment confirming it still
  reproduces, naming the target and any version signal available. Ask first; a comment notifies
  followers.
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
Found while  [what the run was testing, and a link to the oracle if it had one]

Steps to reproduce
  1. ...

Expected     ...
Actual       ...

Evidence
  [screenshot description / response body / console output]
```

Always state the score with its factors and any floor, the oracle, the target and mode plus a
version signal when one exists, and the account with what was confirmed about its state — a
finding whose environment is unrecorded can't be re-checked later, and one found under a
particular persona may reproduce nowhere else.

**Never put a live credential in a filed task.** No token, no password, no minted session id or
access link — a board item is visible to the whole team and outlives the run. Describe the input
by shape and name the endpoint or page; whoever picks the bug up will mint their own.

Report the created item's URL back.
