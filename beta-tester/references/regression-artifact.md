# Regression artifact

A regression test is an *output artifact*, written only after a bug has been confirmed by hand —
never a substitute for actually exercising the running app, and never written speculatively for a
finding that wasn't confirmed.

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

- **Front-end component bug** → a colocated test file next to the component, in the project's own
  test framework (Jest/Vitest + Testing Library, or whatever the sibling files use). Match the
  conventions of the sibling test files next to the component under test — selector strategy,
  mocking approach, assertion style.
- **Backend or API-mode bug** → a test mirroring the project's own source-to-test path convention.
  If the finding is API-mode, mirror the handler/controller/validator that owns the behaviour, not
  the route-definition file.
- **Genuinely browser-only, cross-stack bug with no harness that would run it** → **no artifact**.
  Report the reproduction precisely and say plainly that nothing in this repo can hold it as a
  runnable test. Do not fake coverage.

## Verify it actually runs

Run whatever you wrote with the project's own test command — never assume it passes. If the test
needs infrastructure that isn't available in the current environment (a real database only
present in CI, an external service), say plainly that it's unverified locally rather than
reporting it as passing.
