---
name: speak-simple
description: "Write the document, note, or task the user asked for in short, clear, simple words, with small concrete examples, active voice, and no emojis, em-dashes or contrastive phrasing. Use when the user adds /speak-simple to a writing request (a summary of findings and proposed fixes, an explanation of how a workflow works, a note to remember a discovery, a task or ticket describing a problem), or says: keep it simple, write it simply, make it easy to read, no walls of text, scrivilo semplice, in modo chiaro, senza sbrodolare."
argument-hint: "[what to write]"
---

# Speak simple

The user asked you to write something that persists: a document, a note, a task, a ticket. The user's request sets the content. This skill sets the writing style.

Goal: anyone on the team reads it once and understands it. No second read, no asking the author.

## Rules

1. **Say it once.** Say each thing once. Cut every sentence that adds nothing.
2. **Short sentences.** One idea per sentence. Aim for 20 words or fewer.
3. **Connected prose.** Link related sentences into a short paragraph. Avoid a run of punchy one-line sentences, each on its own line, written for effect.
4. **No emojis.** Use plain text in headings, lists and prose.
5. **Simple words.** Use the common word: "use", "check", "start", "end".
6. **Explain every term.** The first time a technical term, acronym, or internal name appears, say what it is in a few plain words.
7. **Add an example.** When an idea is abstract, add a small example with real names and values.
8. **Most important first.** Start with the point. Details and background come after.
9. **Active voice.** Name who does the action: "the job deletes the file". Use the passive only when an active sentence is grammatically impossible.
10. **Direct statements.** Say what a thing is and what it does. Never define it by what it is not. Avoid the pattern "This is not X, it is Y" and every other contrastive construction ("X, not Y", "rather than", "instead of", "more than just").
11. **No em-dashes.** Never write the em-dash character (`U+2014`). Use a semicolon, a period, or rewrite the sentence so it needs no dash.
12. **Lists for parallel items.** Use a list for three or more items of the same kind: steps, options, findings. Use headings to split topics and code blocks for code. Use a paragraph for reasoning that links one sentence to the next.
13. **Do not mention the reader.** Never write about who the reader is or what level they are.

## Examples of the rules

Rule 1, say it once:

- Bad: "The import fails. As mentioned, the import does not complete. In short, the import is broken."
- Good: "The import fails on files larger than 2 MB."

Rules 2 and 5, short sentences and simple words:

- Bad: "In order to mitigate the aforementioned issue, it is necessary to leverage a retry mechanism that is invoked upon failure."
- Good: "Retry the call when it fails. This fixes the timeout."

Rule 3, connected prose:

- Bad, four lines: "The job runs at night." / "It locks the table." / "Users wait." / "Big problem."
- Good: "The night job locks the `orders` table. Users who save an order during the run wait until it ends."

Rule 4, no emojis:

- Bad: a heading that starts with a bug emoji, then "Login fails".
- Good: "Bug: login fails".

Rule 6, explain the term:

- Bad: "The DLQ is filling up."
- Good: "The DLQ (dead letter queue: where messages go after they fail too many times) is filling up."

Rule 7, add an example:

- Bad: "The parser drops trailing whitespace in some edge cases."
- Good: "The parser drops trailing spaces. Example: `\"abc  \"` becomes `\"abc\"`, so the hash no longer matches."

Rule 8, most important first:

- Bad: "Last week we looked at the logs, then we checked the config, and in the end we found that the token expires after 5 minutes."
- Good: "The token expires after 5 minutes. We found it in the config after checking the logs."

Rule 9, active voice:

- Bad: "The cache is invalidated when the config is changed."
- Good: "Saving the config clears the cache."

Rule 10, direct statements:

- Bad: "This is not a bug in the parser, it is a bug in the input file."
- Good: "The input file has a broken header. The parser reads it as written."
- Bad: "The script is more than just a linter."
- Good: "The script lints the code and fixes the import order."

Rule 11, no em-dashes:

- Bad: "The job runs at night [em-dash] it locks the table.", where `[em-dash]` stands for the real character.
- Good: "The job runs at night. It locks the table."

Rule 12, lists for parallel items:

- Bad: "To set it up you install the package, then you copy the config file, then you set the `API_KEY` variable."
- Good:
  1. Install the package.
  2. Copy `config.example.yml` to `config.yml`.
  3. Set the `API_KEY` variable.

Rule 13, do not mention the reader:

- Bad: "This guide is written so that anyone, even a beginner, can follow it."
- Good: "This guide sets up the project in three steps."

## Shape by request type

Pick the shape that fits. Skip any section that would be empty.

**Findings and proposed fixes**

```markdown
## Summary
One or two sentences: what is wrong and what we propose.

## Findings
### 1. <problem in a few words>
- What happens: ...
- Why: ...
- Example: ...
- Fix: ...
```

**How something works (workflow, system, feature)**

```markdown
## What it does
One or two sentences.

## Steps
1. <first thing that happens>
2. ...

## Example
A real run from start to end, with real values.
```

**Note to remember a discovery**

```markdown
## What we found
One sentence.

## Why it matters
One or two sentences.

## Example
The concrete case that showed it.
```

**Task or ticket describing a problem**

```markdown
## Problem
What goes wrong, in one or two sentences.

## How to reproduce
1. ...

## Expected vs actual
- Expected: ...
- Actual: ...

## Proposed fix
One or two sentences.
```

## Keep exact

Simple wording keeps every fact. Copy these verbatim: code, commands, paths, error messages, numbers, API and product names. Quoted text keeps its own characters too: an em-dash or an emoji inside a quoted error or log line stays as it is.

## Before you save

Re-read the text once. Each check matches the rule with the same number.

1. Can any sentence be cut, or does any fact appear twice?
2. Does any sentence carry two ideas? Split it.
3. Is there a run of one-line sentences on separate lines? Join the related ones into a paragraph.
4. Is there any emoji outside quoted text? Remove it.
5. Is there a long or formal word with a common replacement? Use the common word.
6. Is every technical term explained the first time it appears?
7. Does every abstract idea have an example, where one fits?
8. Is the main point in the first two lines?
9. Is every sentence in the active voice, unless the active form is grammatically impossible?
10. Search for "not ... but", "not X, it is Y", "rather than", "instead of", "more than just". Rewrite each hit as a direct statement.
11. Search for the em-dash (`U+2014`) outside quoted text. Replace each one.
12. Are three or more parallel items written as a sentence? Turn them into a list.
13. Does any sentence talk about the reader's level? Remove it.
