#!/usr/bin/env python3
"""Recognize test files by name, find the test files of a source file, and pick the runner's
language profile for a file.

Usage: testnames.py check PATH [PATH ...]
       testnames.py kind PATH [PATH ...]
       testnames.py match SOURCE [SOURCE ...]
       testnames.py profile PATH

check prints each PATH that is not named like a test file, and exits 1 when there is one.
kind prints "<kind> PATH" for each PATH: test (named like a test file), support (a file the
tests lean on: under a test, mock, snapshot or fixture folder, or a test setup or config file
such as vitest.config.ts or phpunit.xml) or source.
match prints, for each SOURCE (a path from the repo root), the tracked files named like its
tests: "SOURCE: TEST" per match, "SOURCE: none" when there is none. It reads `git ls-files`, so
run it with the target repo as the cwd: python3 <skill>/scripts/testnames.py match src/a.ts.
profile prints the name of the lang/<name>.sh profile whose LANG_EXT lists PATH's extension,
or "none".

The templates are test-guard's (src/config.py _DEFAULT_TEST_PATTERNS and
src/layer2_heuristic.py _match_test_files), with the .mts, .cts, .mjs and .cjs extensions
added to the JavaScript and TypeScript rows, and a template's leading **/ also matching a file
at the repo root. A file is a test when its file name (not its folders) has the marker of a
template for its own extension (MARKERS): Test or Tests at the end for PHP, Java, C#, Swift;
_test for Python and Go; .test. or .spec. for JavaScript and TypeScript; and so on. test-guard
accepts any marker on any extension; tying them to the extension keeps a source file such as
OpenApiSpec.ts out. Added beyond test-guard: the -test., -spec. (NestJS's .e2e-spec.) and
.test-d. markers for JavaScript and TypeScript, and a .rs file under a tests/ folder (Rust's
integration tests). An extension with no row: any marker counts. Tests a name does not show
(Rust's inline #[cfg(test)], a test in a helper file) are not recognized.
"""
import fnmatch
import glob
import os
import re
import subprocess
import sys
from pathlib import PurePosixPath

JS_EXTS = ("js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts")
# id: (source glob, test template); {name} is the source file name without its extension.
PATTERNS = {
    "python": ("**/*.py", "tests/test_{name}.py"),
    "python-suffix": ("**/*.py", "**/{name}_test.py"),
    **{f"{ext}-{kind}": (f"**/*.{ext}", template.format(ext=ext, name="{name}"))
       for ext in JS_EXTS
       for kind, template in (("test", "**/{name}.test.{ext}"), ("spec", "**/{name}.spec.{ext}"),
                              ("dir", "**/__tests__/{name}.{ext}"))},
    "php": ("**/*.php", "**/{name}Test.php"),
    "go": ("**/*.go", "**/{name}_test.go"),
    "java": ("**/*.java", "**/{name}Test.java"),
    "kotlin": ("**/*.kt", "**/{name}Test.kt"),
    "ruby-spec": ("**/*.rb", "**/{name}_spec.rb"),
    "ruby-test": ("**/*.rb", "**/test_{name}.rb"),
    "rust": ("**/*.rs", "tests/{name}.rs"),
    "csharp": ("**/*.cs", "**/{name}Tests.cs"),
    "csharp-single": ("**/*.cs", "**/{name}Test.cs"),
    "swift": ("**/*.swift", "**/{name}Tests.swift"),
    "swift-single": ("**/*.swift", "**/{name}Test.swift"),
    "scala-spec": ("**/*.scala", "**/{name}Spec.scala"),
    "scala-test": ("**/*.scala", "**/{name}Test.scala"),
    "c": ("**/*.c", "**/test_{name}.c"),
    "cpp": ("**/*.cpp", "**/test_{name}.cpp"),
    "cpp-cc": ("**/*.cc", "**/test_{name}.cc"),
    "cpp-cxx": ("**/*.cxx", "**/test_{name}.cxx"),
    "elixir": ("**/*.ex", "test/**/{name}_test.exs"),
    "dart": ("**/*.dart", "test/**/{name}_test.dart"),
    "lua": ("**/*.lua", "**/test_{name}.lua"),
    "lua-spec": ("**/*.lua", "**/{name}_spec.lua"),
}


def _stem_starts(prefix):
    return lambda p: p.stem.startswith(prefix)


def _stem_ends(suffix):
    return lambda p: p.stem.endswith(suffix)


def _js_marked(p):
    return (any(m in p.name for m in (".test.", ".spec.", "-test.", "-spec.", ".test-d."))
            or "__tests__" in p.parts[:-1])


# Test file extension: the name rules that mark a test file with that extension.
MARKERS = {
    **{ext: [_js_marked] for ext in JS_EXTS},
    "py": [_stem_starts("test_"), _stem_ends("_test")],
    "php": [_stem_ends("Test")],
    "go": [_stem_ends("_test")],
    "java": [_stem_ends("Test")],
    "kt": [_stem_ends("Test")],
    "rb": [_stem_ends("_spec"), _stem_starts("test_")],
    "rs": [lambda p: "tests" in p.parts[:-1]],
    "cs": [_stem_ends("Tests"), _stem_ends("Test")],
    "swift": [_stem_ends("Tests"), _stem_ends("Test")],
    "scala": [_stem_ends("Spec"), _stem_ends("Test")],
    "c": [_stem_starts("test_")],
    "cpp": [_stem_starts("test_")],
    "cc": [_stem_starts("test_")],
    "cxx": [_stem_starts("test_")],
    "exs": [_stem_ends("_test")],
    "dart": [_stem_ends("_test")],
    "lua": [_stem_starts("test_"), _stem_ends("_spec")],
}
# Test support: folders that hold what the tests lean on, and test setup or config file names.
SUPPORT_DIRS = {"test", "tests", "__tests__", "spec", "__mocks__", "__snapshots__", "__fixtures__",
                "fixtures"}
SUPPORT_NAMES = ("jest.setup.*", "vitest.setup.*", "setupTests.*", "conftest.py", "phpunit.xml*",
                 "jest.config.*", "vitest.config.*", "playwright.config.*", "cypress.config.*",
                 "karma.conf.*")
ANY_MARKER = [_stem_starts("test_"), _stem_ends("Test"), _stem_ends("Tests"), _stem_ends("_test"),
              _stem_ends("_spec"), _stem_ends("Spec"), _js_marked]
LANG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lang")
LANG_EXT = re.compile(r"""^LANG_EXT=(['"]?)([^'"]*)\1\s*(?:#.*)?$""")


def globmatch(path, pattern):
    """fnmatch, where a leading **/ also matches no folder (a file at the repo root)."""
    return fnmatch.fnmatch(path, pattern) or (
        pattern.startswith("**/") and fnmatch.fnmatch(path, pattern[3:]))


def is_test(path):
    """@returns True when the file name has a test marker for its extension (MARKERS)."""
    p = PurePosixPath(path)
    rules = MARKERS.get(p.suffix.lstrip("."), ANY_MARKER)
    return any(rule(p) for rule in rules)


def kind(path):
    """@returns "test", "support" (SUPPORT_DIRS, SUPPORT_NAMES) or "source"."""
    if is_test(path):
        return "test"
    p = PurePosixPath(path)
    if SUPPORT_DIRS & set(p.parts[:-1]) or any(fnmatch.fnmatch(p.name, g) for g in SUPPORT_NAMES):
        return "support"
    return "source"


def matches(source, files):
    """@returns The files named like a test of SOURCE, in pattern then file order; [] when
    SOURCE is itself a test."""
    if is_test(source):
        return []
    name, found = glob.escape(PurePosixPath(source).stem), []
    for source_glob, template in PATTERNS.values():
        if not globmatch(source, source_glob):
            continue
        test_glob = template.replace("{name}", name)
        found += [f for f in files if globmatch(f, test_glob) and f not in found]
    return found


def profile_of(path):
    """@returns The lang/<name>.sh profile whose LANG_EXT lists PATH's extension, or None."""
    ext = PurePosixPath(path).suffix.lstrip(".")
    if not ext or not os.path.isdir(LANG_DIR):
        return None
    for entry in sorted(os.listdir(LANG_DIR)):
        if not entry.endswith(".sh"):
            continue
        with open(os.path.join(LANG_DIR, entry), encoding="utf-8") as f:
            for line in f:
                hit = LANG_EXT.match(line.strip())
                if hit and ext in hit.group(2).split():
                    return entry[:-3]
    return None


def main(argv):
    if len(argv) < 2 or argv[0] not in ("check", "kind", "match", "profile"):
        sys.stderr.write(__doc__ or "")
        return 2
    cmd, paths = argv[0], argv[1:]
    if cmd == "profile":
        print(profile_of(paths[0]) or "none")
        return 0
    if cmd == "check":
        bad = [p for p in paths if not is_test(p)]
        for p in bad:
            print(p)
        return 1 if bad else 0
    if cmd == "kind":
        for p in paths:
            print(f"{kind(p)} {p}")
        return 0
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                           check=True).stdout.splitlines()
    for source in paths:
        found = matches(source, files)
        for test in found or ["none"]:
            print(f"{source}: {test}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
