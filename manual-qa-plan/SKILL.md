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

### 1. Resolve the range

Ask for the base only if it was not given. Otherwise infer and state the assumption:
last release tag (`git describe --tags --abbrev=0`), the branch point (`git merge-base develop HEAD`), or the PR base.

### 2. Collect the change-set

```bash
scripts/collect_changes.sh <BASE> [HEAD] -o <outdir>
```

Writes `commits.md`, `files.md`, `stat.md`, `flags.md`, `full.diff`.
`flags.md` is the important one: it groups changed files into categories that usually reach the user, and its
**Uncategorised** section lists files no heuristic matched — read those yourself, they are not pre-screened.

Read `full.diff` in full when it is small. When it is large, read it per risk flag and per top-churn file
from `stat.md`, and use `git log -p <BASE>..<HEAD> -- <path>` for anything still unclear.

### 3. Classify every change

Read `references/impact-analysis.md`. It carries the verdict rule, how to recover the previous behaviour from git,
the table of changes that reach the user without looking like it (caching, background jobs, migrations, defaults,
permissions, formatting, error paths), and how to set priority.

Delegate this step to parallel subagents when the range is large — one per risk-flag category, each returning
classified findings — then merge. Do not delegate the writing.

### 4. Write the document

Read `references/writing-test-cases.md` for the case format, the before/after table rules, and a worked
rewrite from a code-level statement into runnable steps.

Copy `assets/qa-plan-template.md` as the skeleton and fill it. Order cases by priority, P1 first.

Cases that confirm something did **not** change are required whenever a shared component was touched.
Label them as regression checks so the result is not misread as "nothing happened".

### 5. Verify before delivering

Do not present the document until all four hold:

- Every path in `files.md` appears in the document — as a case, a "not manually testable" row, or an open question. Check by diffing the two lists, not by impression.
- No case names a class, function, file, or table in its steps. Those belong in the appendix only.
- Every expected result is something a person can observe and compare against, with exact wording where wording is shown.
- Every behaviour that changed has both sides recorded; every case that is a regression check says so.

State which of these checks were run when handing the document over.

## Output location

Write to a durable path in the repository or an agreed docs directory — not a temporary directory.
Ask where it should live if the project has no obvious convention.
