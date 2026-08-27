---
name: changelog
description: Write a descriptive changelog for everything that landed between a starting point (a commit, tag, or branch) and HEAD, grouped into emoji-headed markdown sections a reader can act on, with each entry translated from what the commit did to the code into what changed for the user. Use when asked to write or update a changelog, release notes, "what's new", or a CHANGELOG.md entry, when preparing a release or announcement, or when handed a tag, branch, PR, or commit range and asked what shipped in it.
---

# Changelog

Turn a commit range into a changelog someone outside the codebase can read. The output is a
markdown document, written to a durable path — not an answer in the conversation.

## Step 1: Settle the range, the version, and where it goes

Ask only what cannot be derived:

1. **Range.** The starting point is a commit, tag, or branch; the end is `HEAD` unless
   stated. If the user names a release, prefer the tag over a raw SHA.
2. **Version and date.** Take the version from the range's own tag when one exists. If the
   range is untagged, ask; do not invent a number. The date is the date of the last commit
   in the range, in ISO 8601, unless the release is scheduled for a known later date.
3. **Destination.** A `CHANGELOG.md` at the project root is the default. If one exists, the
   new section goes on top and no published section below is edited.
4. **Audience.** Default to the people who use the software. Ask only if the project's
   existing changelog is plainly written for its own developers — then match it.

## Step 2: Collect the range

```bash
scripts/collect_commits.sh <base-ref> [head-ref] -o <outdir>
```

Writes five files. Read all five:

- `range.md` — commit count, dates, tags in range, nearest earlier tag, merges landed.
- `by-type.md` — commits grouped by conventional-commit prefix. Most groups map straight
  onto a template section; Breaking and Removed have no prefix of their own and are filled
  by hand from `breaking.md`, and a Reverted commit is placed per commit.
- `breaking.md` — `!:` subjects, anything mentioning BREAKING, and reverts.
- `unclassified.md` — every commit whose subject matched no known prefix.
- `contributors.md` — authors in the range.

The grouping is a starting point, not the answer. A `chore:` commit can be user-visible and
a `feat:` commit can be invisible; the prefix records what the author called it, not what
it did.

## Step 3: Account for every commit

Each commit in the range ends up in exactly one of three states, and the third is the one
that keeps the document honest:

1. In an entry, alone or merged with others that are one change to the reader.
2. Under **Internal**, because nothing a user can observe changed.
3. On an open-questions list, because its effect could not be determined from the commit
   and the code it touched.

Everything in `unclassified.md` must be read individually — that file is where a real
change hides behind a subject like "More fixes". Never resolve a commit by guessing from
its subject alone: open the diff when the subject does not settle it.

Reverts need care. A commit and its revert inside one range are usually no entry at all,
but a revert of something released earlier is a change the reader must be told about.

## Step 4: Write the entries

Read `references/writing-entries.md` before writing the first bullet. It carries the entry
shape, the category definitions, the emoji mapping, the before-and-after rewrites, and the
anti-patterns.

The one rule worth stating here: a commit message says what the author did to the code, an
entry says what changed for the reader. Every entry is that translation.

## Step 5: Assemble

Copy `assets/changelog-template.md` and fill it in. Keep its section order exactly:
Breaking, Added, Improved, Fixed, Security, Deprecated, Removed, Internal. Omit an empty
section rather than writing "none", and never reorder them — a reader learns the shape once.

Delete the template's guidance comments before saving.

## Step 6: Verify before handing it over

State which of these were checked:

- Every commit in the range is in an entry, under Internal, or on the open-questions list.
  Say the counts.
- Every commit in `unclassified.md` was read individually.
- Nothing from `breaking.md` is filed anywhere except Breaking changes.
- No entry is a commit subject. No entry says "various", "misc", "minor tweaks", or "bug
  fixes and improvements".
- Version and date are present, the date is ISO 8601, and a Breaking section is not paired
  with a patch-level version bump.
- Security entries describe impact without describing how to reproduce.
- Sections are in template order, and the emoji match the mapping.

If any check fails, fix it before presenting the document. If a commit's effect genuinely
could not be determined, it stays on the open-questions list and is named in the hand-off —
an unresolved commit that is disclosed is workable, one that is silently dropped is not.
