# Regression artifact

A regression test is an *output artifact*, written only after a bug has been confirmed by hand —
never a substitute for actually exercising the running app, and never written speculatively for a
finding that wasn't confirmed.

## Before writing anything

- **Ask first.** The test goes into the user's working tree. Name the file it will create or
  change.
- **The working tree must be the target's source.** If the target was deployed from another
  repository, a different branch, or a version you can't match to this checkout, a test written
  here pins nothing. Say so and skip it.
- **Never commit it.** The test is red until the bug is fixed, and a red test on a shared branch
  breaks everyone's CI. Committing — and where it belongs, in the fix's own change — is the
  user's decision.
- **It is still on disk for every later switch.** Settle the test file with the user *before*
  any branch switch the run makes after writing it: a control run on the base branch (workflow
  step 5 in `SKILL.md`) as much as the switch back in step 10. A new untracked file follows the
  checkout onto the other branch, and a modified tracked file blocks the checkout.

## Find the harness the project actually runs

Don't assume a framework. Detect it:

- Look for CI configuration (a GitHub Actions workflow, a similar CI file) and find the job that
  runs tests — that names the real command and, often, the real runner.
- Look for existing test files near the code the bug lives in, and match their conventions:
  naming, imports, assertion style, how they set up fixtures or mocks.
- If the bug is UI-mode and the project has a browser-automation harness (Playwright, Cypress, or
  similar) that CI **actually runs**, a UI-mode regression can go there. If the project has no
  such harness wired into CI — even if the tooling is installed, or a spec file exists but nothing
  runs it — **do not write one**. A spec nobody runs is worse than nothing, because it looks like
  coverage and isn't. In that case, write the test at whichever layer (front-end component,
  back-end unit/integration) actually reproduces the underlying defect, even if that means the
  test exercises the bug one layer down from where it was observed.

## Route by layer

- **Front-end component bug** → a test file where the project keeps them for that component, in
  the project's own test framework (Jest/Vitest + Testing Library, or whatever the sibling files
  use). Match the conventions of the neighbouring tests — location, selector strategy, mocking
  approach, assertion style.
- **Backend or API-mode bug** → a test mirroring the project's own source-to-test path convention.
  If the finding is API-mode, mirror the handler/controller/validator that owns the behaviour, not
  the route-definition file.
- **Genuinely browser-only, cross-stack bug with no harness that would run it** → **no artifact**.
  Report the reproduction precisely and say plainly that nothing in this repo can hold it as a
  runnable test. Do not fake coverage.

## Verify it fails, for the right reason

The bug is still open, so the test **must fail now** — a test that passes against the buggy code
doesn't capture the bug. Run it with the project's own test command and read why it failed:

- **It fails on the assertion that encodes the expected behaviour** → correct. Report it as red,
  with the assertion message.
- **It errors out instead** — a missing import, a fixture that didn't load, a typo → the test is
  broken, not the product. Fix the test and run it again.
- **It passes** → it doesn't reproduce the bug. Rework it, or drop it and say why.

Then mark it the way the project marks a known-open bug, if it has a convention — an
expected-failure marker, a skip that carries the finding's link — so it doesn't fail the next
person's run before the fix lands. No such convention → leave it plain and say it is red on
purpose.

If the test needs infrastructure that isn't available here (a real database only present in CI,
an external service), say plainly that it's unverified locally. Don't report it as red or as
green.
