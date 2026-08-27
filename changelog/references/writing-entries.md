# Writing changelog entries

Read this at the step that turns commits into entries. Everything here is a rule about
wording, not about structure — structure lives in `assets/changelog-template.md`.

## Contents

- [The one move that matters](#the-one-move-that-matters)
- [Entry shape](#entry-shape)
- [Rewrites, before and after](#rewrites-before-and-after)
- [Categories, and what belongs in each](#categories-and-what-belongs-in-each)
- [Emoji](#emoji)
- [Versions and dates](#versions-and-dates)
- [Anti-patterns that get a changelog ignored](#anti-patterns-that-get-a-changelog-ignored)
- [Sources](#sources)

## The one move that matters

A commit message says what the author did to the code. An entry says what changed for the
reader. Every entry is that translation, and an entry that reads like a commit subject has
not been written yet.

The test: could someone who has never seen the codebase act on this line? If it names a
function, a table, a module, or a ticket and nothing else, no.

## Entry shape

- One bullet per change. Never a paragraph.
- Open with a past-tense verb: Added, Fixed, Improved, Updated, Removed, Redesigned,
  Deprecated, Patched.
- Bold the first clause so the list scans; put the detail after it.
- Name the surface the reader touches — the screen, the command, the endpoint, the setting.
- Say when it applies if it is conditional: "on mobile browsers", "in stores over 10k
  products", "when the token had already expired".
- Link out rather than explaining at length: one sentence plus a link beats five sentences.
- Merge several commits into one entry when they are one change to the reader. Split one
  commit into several entries when it changed several things.

## Rewrites, before and after

| Commit subject | Entry |
| --- | --- |
| `fix: php 8.2 deprecation` | **Fixed a PHP 8.2 deprecation warning** that produced errors in the admin dashboard. |
| `perf: optimize wc_meta query` | **Improved query handling** so product search is faster in large stores. |
| `feat: csv export` | **Added CSV export for form submissions**, from the settings screen. |
| `chore: update translations` | **Updated German and Spanish translations.** |
| `fix: upload validation` | **Patched a vulnerability in file upload handling** that allowed unauthorized file types. |
| `fix: login` | **Fixed login failing on mobile browsers** after a session expired. |

Note the direction of every rewrite: the internal noun (`wc_meta`, `php 8.2 deprecation`)
is replaced by, or subordinated to, the thing the reader observes.

## Categories, and what belongs in each

- **Breaking** — anything that makes a working setup stop working: removed or renamed
  interfaces, changed defaults, new required configuration, raised minimum versions.
  Breaking changes are never filed under Improved or Changed.
- **Added** — capabilities that did not exist.
- **Improved** — the same capability, better: faster, clearer, fewer steps. Also where
  redesigns go.
- **Fixed** — behaviour that was wrong and is now right. Describe the symptom, not the
  patch.
- **Security** — enough for the reader to judge urgency and act. Never enough to
  reproduce: no payloads, no exact versions of the vulnerable path, no bypass steps.
- **Deprecated** — still works, will not forever. Give the replacement and the date or
  version it stops working.
- **Removed** — gone. Give the replacement.
- **Internal** — invisible to the reader: dependency bumps, refactors, tests, CI. Keep it
  brief or omit it. If everything in a release is internal, say that plainly rather than
  inflating it.

A commit can be genuinely user-invisible. That is a real category, not a failure — file it
under Internal and move on. What is not acceptable is leaving it out with no decision.

## Emoji

One emoji per category heading, never inside an entry. They are scanning aids: a reader
skipping to the fixes should find them by shape.

| Category | Emoji |
| --- | --- |
| Breaking changes | ⚠️ |
| Added | ✨ |
| Improved | ⚡ |
| Fixed | 🛠️ |
| Security | 🔒 |
| Deprecated | ⏳ |
| Removed | 🗑️ |
| Internal | 🧹 |

Keep this mapping stable across releases — a category that changes emoji reads as a
different category. Two of the largest published changelogs surveyed for this skill
(Vercel, Slack) use no emoji at all, so if a project prefers plain headings, drop the
column entirely rather than using emoji inconsistently.

## Versions and dates

- Every release section carries a version and a date. A missing date is one of the most
  common complaints about real changelogs.
- Dates in ISO 8601: `2026-08-27`. No locale-specific formats.
- Reverse chronological: newest release at the top.
- Semantic versioning, if the project uses it: MAJOR for breaks, MINOR for additions,
  PATCH for fixes. A release with a Breaking section and a PATCH bump is a contradiction —
  flag it rather than publishing it.
- Untagged range: derive the version from the project's own scheme if one is evident, and
  otherwise leave `[UNRELEASED]` and say so. Never invent a version number.

## Anti-patterns that get a changelog ignored

- "Bug fixes and improvements." The canonical failure. It tells the reader nothing and
  teaches them not to read the next one either.
- Omitting dates.
- Pasting commit subjects, or a raw `git log`.
- Detail that swings release to release: thorough one version, one line the next.
- Burying a breaking change in a Changed bullet.
- Skipping security entirely, or over-describing it into a working exploit.
- "Various UI updates", "minor tweaks", "misc" — every one of these is an entry nobody
  finished writing.
- Reordering or renaming sections between releases.

## Sources

Format and wording rules above are drawn from:

- <https://dev.to/_estheradebayo/how-to-write-a-proper-changelog-1pa6>
- <https://developer.wordpress.org/news/2025/11/the-importance-of-a-good-changelog/>
- <https://quickhunt.app/blog/what-is-a-changelog>
- <https://vercel.com/changelog> — dated entries, headline plus one sentence, no emoji
- <https://slack.com/intl/it-it/release-notes/mac> — version plus date, category
  subheadings, no emoji
- <https://keepachangelog.com> — the Added/Changed/Fixed/Deprecated/Removed/Security set
  that the first three sources all restate
