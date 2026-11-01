# Write failing tests: {{TASK_NAME}}

## Rules (read twice)
- Answer with the file edits NOW, in this reply. Do not describe a plan or announce what you
  will do: there is no second turn.
- You may edit ONLY these files: {{WRITE_FILES}}. Every other file is read-only, and an edit
  anywhere else is undone automatically.
- The code under test does NOT exist yet. That is the point: a test that fails because a
  function, export or rule is missing is the CORRECT result. Never create, stub or change
  source files to make a test compile or pass.
- Every test asserts real behaviour with the exact values given below. Never write a
  placeholder: no `throw new Error('not implemented')`, no `expect(true)`, no `.skip`, no
  `.todo`, no empty body. If you cannot write a test, leave it out and say why.
- Keep every existing test unchanged. Append the new tests at the end of the named file.
- Copy the style of the existing tests in the same file: {{STYLE_NOTES}}

## What the code will provide (do not implement it)
{{INTERFACES}}

## Tests to add (names exact)
{{TESTS}}

## Example of one finished test in this project's style
```{{LANG}}
{{EXAMPLE_TEST}}
```

## When you are done
List each test you added and the one-line reason it fails today.
