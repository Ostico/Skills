# Runner profile: PHP (PHPUnit). Sourced by run_aider_tests.sh; the patterns run over the added
# lines of tests.diff and the test output.
# shellcheck shell=bash disable=SC2034
LANG_LABEL='PHP (PHPUnit)'
# The extensions this profile is picked for (testnames.py profile).
LANG_EXT='php'
# Tests are counted by review_stats.py's splitter (methods named test* or marked #[Test] / @test,
# new in the model's version): one method often has both marks, so a line count would count it
# twice.
TEST_RE=''
COUNT_TESTS=splitter
# Skipped, incomplete or always-passing tests, and an empty test body on one line.
PLACEHOLDER_RE='markTestIncomplete|markTestSkipped|assertTrue\(\s*true\s*\)|assertSame\(\s*1\s*,\s*1\s*\)|function test\w*\([^)]*\)[^{]*\{\s*\}'
# A test file that does not parse, as PHPUnit or php -l report it.
PARSE_RE='PHP Parse error|ParseError|Parse error: syntax error|syntax error, unexpected'
# php -l on each --write file (needs php on PATH): one line per file that does not parse.
lang_parse_check() {
  command -v php > /dev/null || return 0
  php -l "$1" 2>&1 | grep -E 'Parse error|Errors parsing' || true
}
