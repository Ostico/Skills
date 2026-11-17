# Language rules

The steps in SKILL.md hold for every language. This file adds, per language, what the measured
runs taught: rules for the helpers, the brief and the review, the usual commands, and the
runner's profile (`scripts/lang/<name>.sh`: the extensions it is picked for, `LANG_EXT`; how to
count added tests, the placeholders and the parse errors of that language). A new profile needs
only its file: `scripts/testnames.py` picks it by `LANG_EXT`, for the runner and for
`review_stats.py`, which splits tests only for the languages it has a splitter for (`SPLITTERS`).
Whether a file is a test file goes by its file name, for any language (`testnames.py check`,
test-guard's naming rules tied to the file's extension: `test_x` and `x_test` for Python,
`xTest` for PHP and Java, `x.test.*`, `x.spec.*`, `x-test.*`, `x-spec.*`, `x.test-d.*` or a
`__tests__/` folder for JavaScript and TypeScript, a `tests/` folder for Rust, and so on; the
docstring lists them all). The runner passes its `--lang` to `review_stats.py`, so a file
whose extension is not in `LANG_EXT` is still split by that profile.

A language has a section here only once runs in it are measured (`findings.local.md`). For a language
without a section:
- say so to the user before the run;
- use the generic rules only; the runner skips the test count and the parse check, and
  `review_stats.py` compares whole files instead of test by test;
- treat the run as a measurement, record it, and write the section from what went wrong.

## JavaScript / TypeScript

Measured: every run in `findings.local.md` (vitest, strict TypeScript, Node). Runner profile:
`scripts/lang/js.sh`, picked for `.ts .tsx .mts .cts .js .jsx .mjs .cjs`.

Commands:
- fix: `npx prettier --write <test files> && npx eslint --fix <test files>`;
- test: `npx vitest run <test files>` (or the project's runner), in the package folder;
- why each test fails (Step 5): `scripts/stub_run_vitest.sh`. It writes into `OUT/stub/` a
  stub per missing module (each export a function that throws, or a constant the tests need
  true) and a config that copies the project's with spreads, sets `root` to the package folder
  and aliases the modules to the stubs; then runs the tests and prints one line per test:

  ```bash
  bash scripts/stub_run_vitest.sh --pkg <package folder> --out <OUT> \
    --stub '<dir>/<module>.ts:<export>,<export>,<CONSTANT>=<value>' [--stub ...] \
    [--no-global-setup] -- <test files>
  ```

  `--no-global-setup` leaves out a `globalSetup` the stub run must not start (a database
  container). Why it is a script: nothing in `OUT/` resolves a bare import (`vitest/config`),
  `mergeConfig` concatenates arrays (a `globalSetup` cannot be taken out), and Vite replaces the
  part of the specifier an alias regex matches (a regex on the end only leaves `../` in front).
  For a project config it cannot read (vitest `projects`, a config that needs the environment),
  write the config by hand on the same lines. It touches nothing in the repo. It lists apart the
  tests that hang until vitest's timeout instead of failing: each waits for something only the
  new code sends (the brief's wait rules, Step 3).

Helpers Claude writes before the run (the model writes these badly):
1. Child processes: a helper that runs the child as an ES module and loads the code under test
   by `pathToFileURL` of its source; the model's own children never imported it.
2. Processes that must act together: a helper that starts them, waits for each to say ready,
   then releases them at once (a go file).
3. A child that calls back a server in the same process: async `execFile` or `spawn`, never
   `spawnSync`, which blocks the event loop the server needs.
4. TLS: a client that trusts the test CA's certificate, not the leaf certificate; a request helper
   per listener in the protocol it speaks (plain HTTP or TLS).

Rules for the brief (copy them into the brief's rules when they apply):
5. Time: `vi.useFakeTimers()` or the code's own clock option; never `sleep` or a real `setTimeout`
   to wait for something.
6. Ordering: pause a transaction or a call with a gate (a promise the test resolves), then make
   the outside call; say in the facts which call is outside and which is inside.
7. Every promise is awaited: `await expect(p).rejects.toThrow('<message>')`, never a bare
   `expect(p).rejects`.
8. Constants ending in `_MS` are milliseconds; give any other unit in the facts.
9. Server tests: start the server with the project's starter helper and name it in the facts;
   never a config object built by hand, never a fixed port (listen on port 0).
10. Constants and fields: "import `<NAME>` from `<module>`" for each field the tests use and each
   constant they need to build an input or compute; the model hard-coded a timing constant and
   invented a field on the server object. A value the plan gives is asserted as a literal.
11. A helper with an order (install the fake clock before the server starts) gets that order in
   the facts.
12. The accepted case of a refusal: the refused input spread with one key changed,
   `{ ...<base>(), '<key>': '<value>' }`, written so in the facts.
13. Each lock, server, process or listener is released once: one `onTestFinished` registered
   right after it is taken, and no second release at the end of the test.
14. The test runner's API (`test`, `expect`, `vi`, `onTestFinished`, ...) is imported from
   `vitest`, never from the helpers file; the model imported `onTestFinished` from the helpers.
15. Events: `once(...)`, `waitFor(...)` or the promise for an event is created before the
   action that causes it; an answer and the next message can arrive in one chunk, so a
   listener added after the action misses the event and the test hangs.
16. A spy on a logger other code also writes to: filter its calls by message
   (`spy.mock.calls.filter(([m]) => m === '<message>')`), never `toHaveBeenCalledTimes(n)` on
   the whole spy, which counts every other line logged at that level.
17. A test name with an apostrophe: give it in double quotes and say so in the facts; copied
   into single quotes, it broke the file's parse four times.
18. Name the matchers the project has ("no jest-dom: use `.not.toBeNull()`") and each test
   file's relative path to the helpers.
19. A form the project's lint requires (`as unknown` on a nested `expect.any`): give it in the
   brief; the model did not copy it from the style file.

Always copy into the brief's rules, with strict TypeScript (the model broke each of these in
three runs in a row, and each costs a fix):
20. No non-null `!`: guard the value, or assert it with `expect` first.
21. `JSON.parse(...) as <Type>`, never an untyped parse.
22. No `mock.calls[i][j]` (`noUncheckedIndexedAccess`): `toHaveBeenCalledWith(...)`, or
   `toEqual` on the whole `mock.calls`.
23. A fake object gets its type (`const x: <Type> = { ... }`), not a bare `{}`.
24. No `async` function without an `await` in it.

What the review checks first (the model's usual defects):
25. Weak assertions: `toBeDefined`, `toBeTruthy` or `toBeInstanceOf(Error)` where the plan gives
   a value or a message.
26. A missing `await` (grep each `.rejects` for its `await expect(`: eslint's warning hides
    among RED's errors), or a `try`/`catch` that swallows the failure; a file read right after a
    fake-clock tick, outside `vi.waitFor`, when the code writes it asynchronously.
27. Spies restored with `onTestFinished`, not at the end of the test (a failed assertion leaks
    them).
28. Strict TypeScript fixes are expected and count as small: no non-null `!`, no unused
    bindings or imports (`eslint --fix` does not remove an unused import), guarded indexed
    access (`noUncheckedIndexedAccess`), an import from
    `node:timers/promises` shadowing a global.
29. In RED, `tsc` and eslint's `no-unsafe-*` rules fail on the types that do not exist yet; that
    is expected, not a defect of the tests. A rule that fires only on the old signature of the
    code under test (`no-confusing-void-expression` while it returns void) goes to the runner's
    `--red-lint-ok`.

## PHP (PHPUnit)

Measured: two runs in `findings.local.md` (2026-11-04, reflection tests; 2026-11-05, a controller
suite against a real database), both on ds4. Runner profile: `scripts/lang/php.sh`, picked for
`.php`: added tests counted by `review_stats.py`'s splitter (methods named `test*` or marked
`#[Test]` / `@test`; one method often has both), `php -l` on each test file, placeholders
`markTestIncomplete`, `markTestSkipped`, `assertTrue(true)` and a one-line empty test body.

Commands:
- fix: the project's formatter, when it has one (`php-cs-fixer fix <test files>`); with none,
  leave `--fix-cmd` out and expect spacing fixes;
- test: `vendor/bin/phpunit <test files>` (or the project's runner), with `--filter` for the
  new tests;
- why each test fails (Step 5): no stub step. A method that does not exist yet fails each test
  on its own `Error` (`Call to undefined method`), and PHPUnit prints one reason per test; to
  check that a test catches a wrong implementation, run it against a mutated copy of the source
  (`findings.local.md`, 2026-11-04).

Brief rules:
1. A regex or an escaped namespace string goes in the facts as code, quoted as the file quotes
   it (four backslashes inside single quotes): the model copies it exactly.
2. A suite against a real database: the exact SQL each assertion reads, the cleanup in
   `finally`, and the `try` / `fail` / `catch` / `finally` pattern, as code. The model used each
   one as given; the brief is about three times the usual size (5.9 KB for 15 tests).
3. Test doubles: `createStub` in `setUp` for collaborators no test checks; `createMock` only in
   the test that sets expectations on it.
4. A string the code builds: give it in the facts as the code's exact expression.

What the review checks first (the forms of "failure swallowed" seen):
5. `catch (Exception $e)` in the same `try` as `$this->fail()`: PHPUnit's
   `AssertionFailedError` extends `Exception`, so the catch swallows the failure. Rethrow it
   first: `catch (AssertionFailedError $e) { throw $e; }`.
6. `expects($this->exactly(n))` with no check on the arguments passes when the same value is
   sent n times: record the arguments (`willReturnCallback`) and assert the list.
7. The project's spacing (`( $x )`, `[ 'k' ]`) dropped in places, even with a style file:
   small fixes, gone with a formatter in `--fix-cmd`.
