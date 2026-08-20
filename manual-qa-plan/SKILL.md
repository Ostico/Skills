---
name: manual-qa-plan
description: Generate a manual test plan document from a range of commits (a base commit, tag, or branch through HEAD), listing every change that could alter how the application behaves, with step-by-step instructions someone can follow without reading the code, the expected result of each, and a previous-versus-new comparison where behaviour changed. Use when asked to produce a QA plan, manual test plan, regression checklist, release test document, "what needs testing in this release", "what should QA check before we ship", or to hand a diff, PR, branch, or version range to a tester.
---

# Manual test plan from a commit range

Turn `<BASE>..HEAD` into a document a person can execute against the running application without reading source code.

**Two rules that override convenience:**

1. **Account for every changed file.** Each one is either a test case, an explicit "not user-visible" entry with a reason, or an open question. Silent omission makes the document untrustworthy.
2. **Never state or imply the reader's experience level** anywhere in the output — no "junior", "beginner", "simple", "obviously", "just". Write completely and plainly.

## Workflow

### 1. Resolve the range, and settle where the document goes

Ask for the base only if it was not given. Otherwise infer and state the assumption:
last release tag (`git describe --tags --abbrev=0`), the branch point (`git merge-base develop HEAD`), or the PR base.

Settle the output location now rather than at the end. If the project keeps its documentation in a submodule or
a separate repository, delivering means a commit there plus a pointer bump in the parent — say so up front, so
"written" is not mistaken for "delivered". Ask where it should live if the project has no convention.

### 2. Collect the change-set

```bash
scripts/collect_changes.sh <BASE> [HEAD] -o <outdir>
```

Writes `commits.md`, `files.md`, `stat.md`, `flags.md`, `commit_details.md`, `full.diff`.

**Read `commit_details.md` first.** It carries each behaviour commit's subject, full body and per-file stat,
with pointer-bump and docs-only commits filtered out. On a repository whose commit messages state the previous
behaviour, the new behaviour and the reachability, this is the fastest route to a test case by a wide margin —
a 900KB diff can take hours to yield what the bodies give in twenty minutes. Where the bodies are thin, fall
back to the diff.

A commit body is the author's claim, not evidence. Spot-check each one you rely on against the diff, and apply
the verdict rule below: where they disagree, the code wins.

`flags.md` groups changed files into categories that usually reach the user. Read its header: it prints the
count per category and the percentage that matched no heuristic. **When that percentage is high, the grouping
has failed and you must slice the file list yourself** — on a large application the uncategorised bucket is
where the storage, caching and templating layers land, which is to say the highest-impact changes in the range.

Read `full.diff` in full when it is small. When it is large, read it per risk flag and per top-churn file
from `stat.md`, and use `git log -p <BASE>..<HEAD> -- <path>` for anything still unclear.

Read the generated files with a file-reading tool. Do not `cat` them: on some setups shell output passes
through a filter that mangles multi-line text, and you will waste calls before noticing.

### 3. Classify every change

Read `references/impact-analysis.md`. It carries the verdict rule, how to recover the previous behaviour from git,
the table of changes that reach the user without looking like it (caching, background jobs, migrations, defaults,
permissions, formatting, error paths), and how to set priority.

Delegate this step to parallel subagents when the range is large — one per risk-flag category. Do not delegate
the writing.

**Each subagent writes its report to `<outdir>/classification-<category>.md` and returns only that path.**
Then read the files. Do not depend on a subagent's return value arriving: a dropped result costs you the whole
run, and a file on disk survives it. Give every subagent an explicit slice — the exact list of paths it owns —
and account for the slices before you dispatch, so no path is unassigned and no slice names a path that is not
in the diff.

Tell each subagent it is read-only **with respect to the repository**: it may not edit, create, or delete
anything under the repository, and may run no command that changes the working tree. It writes only its own
report, under `<outdir>`. It is classifying changes, not fixing them. The same holds for you, apart from writing
the plan document itself.

If a subagent produces no file, classify that slice yourself and say so when you hand the document over. Never
present a slice as classified when nobody classified it.

### 4. Write the document

Read `references/writing-test-cases.md` for the case format, the before/after table rules, and a worked
rewrite from a code-level statement into runnable steps.

Copy `assets/qa-plan-template.md` as the skeleton and fill it. Order cases by priority, P1 first.

Open with a **case index**: one row per case giving its ID, its surface, its one-line summary and its priority,
then a line naming the cases that cannot be started without a particular tool. A tester should be able to plan
the session from that table alone, without reading a single case.

**Every case states its surface** — where the work is actually done. This is the first thing a tester needs and
the easiest thing to leave implicit:

- the browser interface
- an API client — name the project's own convention if it has one, and its environment
- a mail client, where what is being tested is what the client does to the text
- a shell, for operator commands
- browser devtools, where the check is on a response rather than a screen

Say so explicitly when a case is **not reachable from the interface at all**, and why — an unknown identifier,
a parameter combination no screen sends, a batch size no form assembles. Otherwise a tester will hunt for a
button that does not exist. Where a case mixes surfaces, mark the switch on the step. And when the interface
constrains an input the server rule needs — a field with its own length cap, a form with its own item limit —
that case belongs on the API surface, or it cannot be run at all.

Cases that confirm something did **not** change are required whenever a shared component was touched.
Label them as regression checks so the result is not misread as "nothing happened".

### 5. Verify before delivering

Run the checker, do not eyeball it:

```bash
scripts/verify_coverage.sh <outdir>/files.md <document>
```

It reports any changed path the document never mentions. **Globs do not count as coverage** — writing
`lib/View/templates/**` in the not-testable table reads as complete and hides every file beneath it. Enumerate.

Do not present the document until all five hold:

- Every path in `files.md` appears in the document — as a case, a "not manually testable" row, or an open question. The checker proves this; impression does not.
- No case names a class, function, file, or table in its steps. Those belong in the appendix only. Routes, URLs and screen names are not code and belong in the steps.
- Every case states its surface, and every case a tester cannot start without a tool says which tool.
- Every expected result is something a person can observe and compare against, with exact wording where wording is shown.
- Every behaviour that changed has both sides recorded; every case that is a regression check says so.

State which of these checks were run when handing the document over, and name any slice you classified yourself
because a delegate returned nothing.

## Output location

Write to a durable path in the repository or an agreed docs directory — not a temporary directory.
Ask where it should live if the project has no obvious convention.
