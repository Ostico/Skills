# Make the failing tests pass: {{TASK_NAME}}, {{GROUP}}

## Rules (read twice)
- Answer with the file edits NOW, in this reply. Do not describe a plan or announce what you
  will do: there is no second turn.
- You may edit ONLY these files: {{WRITE_FILES}}. Every other file is read-only. The tests are
  read-only too: an edit to a test file, or to any file not listed here, fails the whole run.
- Make the tests in {{TEST_FILES}} pass. Write no code that no test asks for: a line no test
  runs is a line nobody checked.
- Never add a comment that hides code from the coverage report (`istanbul ignore`,
  `c8 ignore`, `@codeCoverageIgnore`): every line you add must be run by a test.
- Follow "Per file" exactly: the signatures, the messages and the order of the calls it gives
  are the design. Do not rename, reorder or add a parameter; copy each message character for
  character.
- Write real code only. No placeholder, no `TODO`, no "not implemented" error, no empty body:
  a stub makes a test fail later in a harder place. If you cannot write a part, leave the file
  as it was and say why.
- Never silence the type checker: no cast, no `any`, no non-null assertion, no ignore
  comment. Fix the type instead; a cast hides the bug the type checker found.
- Do not think aloud in comments. Write each function once; do not leave a half-written one
  behind to write it again under another name.
{{LANGUAGE_RULES}}
- Style: copy {{STYLE_FILE}} (imports, header comment, doc comments, error handling).

## The task
{{PLAN_FILE}} is the plan for this task: section {{PLAN_SECTION}}. This run writes
{{GROUP}} of it. The tests in {{TEST_FILES}} fail today; they pass when the code below exists.

## Per file
{{PER_FILE}}

## Facts
{{FACTS}}

## When you are done
For each file you changed, list the functions you wrote or changed and the tests they make
pass.

<!--
How to fill this (delete this comment):
- {{TASK_NAME}}: the task's name in the plan.
- {{GROUP}}: which group of the task this run writes, as "group <n> of <total>: <files>".
  One group is one or two source files, in dependency order.
- {{WRITE_FILES}}: each --write path in backticks. The runner reads this line and stops before
  the run when it differs from the run's --write files (a brief written for another run).
- {{PLAN_FILE}} and {{PLAN_SECTION}}: the plan file's path and the section of this task.
- {{TEST_FILES}}: each test file this group must turn green, in backticks.
- {{PER_FILE}}: for each --write file, its path as a heading line, then as code: every
  signature the file exports or changes, every error or log message, and the order of the
  calls inside each function. The measured runs reached green tests with no logic fix only
  when the plan gave this. A new file: "`<path>`: a new file, write it whole", then the same.
- {{FACTS}}: only what the plan, the tests and the --read files do not say, as short bullets:
  a helper's name and signature not in a --read file, a name that reads two ways, a value the
  plan leaves open. Write "none" when there are none. Every line here is output Claude pays
  for: copy nothing the model can read itself.
- {{LANGUAGE_RULES}}: the rules from the project's style or language notes that apply to this
  code, one bullet each; delete the line when none apply.
- {{STYLE_FILE}}: one source file of the project written in the house style, in backticks.
- Pass the plan section, the test files, the interfaces the code uses and {{STYLE_FILE}} with
  --read.
-->
