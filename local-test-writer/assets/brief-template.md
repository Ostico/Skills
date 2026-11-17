# Write failing tests: {{TASK_NAME}}

## Rules (read twice)
- Answer with the file edits NOW, in this reply. Do not describe a plan or announce what you
  will do: there is no second turn.
- You may edit ONLY these files: {{WRITE_FILES}}. Every other file is read-only, and an edit
  anywhere else is undone automatically.
- The code under test does NOT exist yet, or does not do this yet. A test that fails because a
  module, function, export or rule is missing is the CORRECT result. Never create, stub or
  change source files to make a test compile or pass.
- Every test asserts real behaviour with exact values. Never write a placeholder: no "not
  implemented" error, no assertion that always passes, no skipped or todo test, no empty body.
  If you cannot write a test, leave it out and say why.
- Time goes through fake timers or the code's own clock option, never a real sleep or wait.
- Use the test helpers for every setup they cover (processes, servers, sockets, certificates,
  clocks, data); do not write your own, and never build that setup or its config by hand.
- Never invent a name the code provides: use only the fields and functions the --read files or
  the facts name.
- Assert each value the plan gives as the plan writes it. Import a constant from its module only
  to build an input or to compute a value the plan does not give; never type a constant's value.
- A test of a refusal also asserts its accepted case. Build the refused input and the accepted
  one in code from the same base value, with one field or argument changed. Change one input at
  a time, never two.
- Every lock, server, process or listener a test takes is released exactly once.
- Start waiting for an event (a listener, a promise for it) before the action that causes it,
  never after: the event can arrive before the wait starts, and the test hangs.
- A wait for an event only the new code sends also ends on what the old code sends instead (its
  answer or its error), and the test asserts after it: in RED the test must fail, not hang
  until the timeout.
- Wait for the event that ends the operation (the server's answer, its done message), never for
  a step in the middle (a log file that grows before the operation ends): an assertion after a
  middle step runs too early.
- Write each test once. Do not think aloud in comments, and do not leave a half-written test
  behind to write it again under another name.
- Keep every existing test unchanged, except the ones under "Existing tests that change": make
  exactly the change each line gives. Append new tests at the end of the named file: replace
  its last lines, given under "Where new tests go", with the same lines followed by the tests.
{{LANGUAGE_RULES}}
- Style: copy {{STYLE_FILE}} (imports, header comment, doc comments, assertion style).

## The task
{{PLAN_FILE}} is the plan for this task: section {{PLAN_SECTION}}. Its interfaces are what the
code will provide (do not implement them); write every test its test step names, with those
names copied character for character (the same quotes and spaces), and take the values from it.

## Where new tests go
{{FILE_ENDS}}

## Existing tests that change
{{EXISTING_CHANGES}}

{{FACTS}}

## When you are done
List each test you added and the one-line reason it fails today.

<!--
How to fill this (delete this comment):
- {{LANGUAGE_RULES}}: the brief rules of the language's section in references/languages.md
  that apply to these tests, and every rule that section says to always copy, one bullet each;
  delete the line when none apply.
- {{WRITE_FILES}}: each --write path in backticks. The runner reads this line and stops before
  the run when it differs from the run's --write files (a brief written for another run).
- {{FACTS}}: only what the plan and the --read files do not say, as short bullets. Each fact
  starts with the test or tests that use it ("`<test name>`: ..."), or "all tests:"; the model
  skips a fact that names no test.
  - the accepted case of each refusal test, as code, in that test's own line: the model skipped
    accepted cases given in a general list;
  - a helper's name and signature when the tests need it and it is not in a --read file;
  - how a name is used, when it reads two ways: "`x` is a method of the object, not an option"
    or "`<type>` has no field `<y>`" for a field the tests would expect;
  - what the code does today, when a test checks a behaviour that is not there yet and today's
    answer looks close to the right one (today one error code, after the task another): the
    test asserts the new value;
  - one line per pair of behaviours that read alike, saying what separates them (e.g. "a call
    made during a transaction comes from code outside the transaction's function and waits; a
    call from inside the function is refused");
  - a value the plan leaves open that the tests must pin;
  - every expected value that follows from a rule of the plan, worked out as a number for each
    test that checks it (the rule alone is not enough: the model gets the arithmetic wrong).
- {{FILE_ENDS}}: for each --write file that exists and gets new tests, its path in backticks
  and its last lines exactly (3 to 5, ending at the file's last line, enough to be unique) in a
  code block. A new file: "`<path>`: a new file, write it whole". A model given no anchor
  started an edit to append, broke it off and wrote it again: aider applied neither.
- {{EXISTING_CHANGES}}: one line per existing test the task changes or deletes, the test's name
  first, in backticks: "- `<test name>`: <the change>" or "- `<test name>`: delete". The runner
  reads this section: a change to a test named here is reported as briefed, any other change to
  an existing test is a finding. It matches a name only in backticks, character for character
  as in the file (a name may wrap over two lines). A mechanical change to many tests goes on one
  line as a pattern, "- all tests: `<old text>` -> `<new text>`" (one pair per line, several
  lines for several): a test whose only changes are those replacements is reported as briefed.
  A rename and a new expected value of the same test go on two lines: on one, the model made
  the value change and skipped the rename.
  When none change, keep the heading and write "none".
  Leave it empty when the plan and the files cover everything. Every line here is output Claude
  pays for: copy nothing the model can read itself.
- Pass the plan section, the sources the tests import, the test helpers and {{STYLE_FILE}}
  with --read.
-->
