---
name: speak-simple
description: "Write the document, note, or task the user asked for in short, clear, simple words, with small concrete examples. Use when the user adds /speak-simple to a writing request (a summary of findings and proposed fixes, an explanation of how a workflow works, a note to remember a discovery, a task or ticket describing a problem), or says: keep it simple, write it simply, make it easy to read, no walls of text, scrivilo semplice, in modo chiaro, senza sbrodolare."
argument-hint: "[what to write]"
---

# Speak simple

The user asked you to write something that persists: a document, a note, a task, a ticket. This skill sets how you write it. The content is the user's request; the style is this file.

Goal: anyone on the team reads it once and understands it. No second read, no asking the author.

## Rules

1. **Short.** Say each thing once. Cut every sentence that adds nothing.
2. **Simple words.** Use the common word. Write "use", not "leverage". Write "check", not "perform a validation".
3. **Short sentences.** One idea per sentence. Aim for 20 words or fewer.
4. **Explain every term.** The first time a technical term, acronym, or internal name appears, say what it is in a few plain words.
5. **Show, don't only tell.** When an idea is abstract, add a small example with real names and values.
6. **Most important first.** Start with the point. Details and background come after.
7. **Active voice.** Write "the job deletes the file", not "the file is deleted".
8. **Structure helps scanning.** Use headings, short lists, and code blocks. Prefer a list to a long paragraph.
9. **Do not mention the reader.** Never write about who the reader is or what level they are. Just write clearly.

## Examples of the rules

Rule 2 and 3, simple words and short sentences:

- Bad: "In order to mitigate the aforementioned issue, it is necessary to leverage a retry mechanism that is invoked upon failure."
- Good: "Retry the call when it fails. This fixes the timeout."

Rule 4, explain the term:

- Bad: "The DLQ is filling up."
- Good: "The DLQ (dead letter queue: where messages go after they fail too many times) is filling up."

Rule 5, add an example:

- Bad: "The parser drops trailing whitespace in some edge cases."
- Good: "The parser drops trailing spaces. Example: `\"abc  \"` becomes `\"abc\"`, so the hash no longer matches."

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

Simple wording never changes facts. Keep these verbatim: code, commands, paths, error messages, numbers, API and product names.

## Before you save

Re-read the text once and check:

- Is the main point in the first two lines?
- Can any sentence be cut without losing a fact?
- Is every technical term explained the first time it appears?
- Does every abstract idea have an example, where one fits?
- Does any sentence talk about the reader's level? Remove it.
