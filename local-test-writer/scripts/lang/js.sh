# Runner profile: JavaScript and TypeScript (vitest, jest, mocha, node:test). Sourced by
# run_aider_tests.sh; the patterns run over the added lines of tests.diff and the test output.
# shellcheck shell=bash disable=SC2034
LANG_LABEL='JavaScript/TypeScript'
# The extensions this profile is picked for (testnames.py profile).
LANG_EXT='ts tsx mts cts js jsx mjs cjs'
# One added line per test: test(...), it(...), test.each(...)(...), test.concurrent(...).
TEST_RE='^\+\s*(test|it)(\.each\(.*\))?(\.\w+)?\('
# Skipped, todo or always-passing tests (added to the generic placeholder words).
PLACEHOLDER_RE='\.skip\(|\.todo\(|\.fails\(|expect\(true\)|expect\(1\)\.toBe\(1\)'
# Lint errors expected in RED (types of code that does not exist yet): not findings.
FIX_EXPECTED_RE='no-unsafe-|Unsafe (assignment|call|member access|argument|return)'
# An error line in the fix command's output (eslint's stylish format).
FIX_ERROR_RE='^\s*[0-9]+:[0-9]+\s+error\s'
# A test file that does not parse, as vitest/esbuild/tsx/node report it.
PARSE_RE='SyntaxError|Transform failed|ParseError|Unexpected token|ERROR: Expected|Expression expected'
