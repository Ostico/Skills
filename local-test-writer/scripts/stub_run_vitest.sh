#!/usr/bin/env bash
# Run vitest tests with missing modules replaced by stubs that throw, to see why each test fails
# (Step 5), not only the first missing import. Writes everything into OUT/stub/; the repo is not
# touched.
#
# Usage:
#   stub_run_vitest.sh --pkg DIR --out DIR --stub 'SPEC:EXPORT[,EXPORT|,NAME=VALUE ...]' [--stub ...]
#                      [--config FILE] [--no-global-setup] -- TEST_FILE [TEST_FILE ...]
#
# --pkg      the package folder: vitest runs there, with its own vitest and its config.
# --out      the run's OUT folder; the stubs, the config and output.txt go in OUT/stub/.
# --stub     one missing module: SPEC is its path as the tests import it, from a folder down
#            (src/auth.ts; any ../ before it and the extension .ts/.js/.mts/... all match),
#            then its exports. A plain NAME is a function that throws when called or built with
#            new; NAME=VALUE is a constant the tests need true (TIMEOUT_MS=60_000), VALUE a
#            JavaScript expression; `default` is the default export.
# --config   the project's config (default: the first vitest.config.* or vite.config.* in --pkg).
# --no-global-setup  leave out the config's globalSetup (a database container the stub run must
#            not start).
# The project's config is copied with spreads, not mergeConfig (which concatenates arrays), and
# root is set to --pkg, so include and setupFiles resolve as in the project. Prints each test's
# line from the verbose reporter, the tests that hang until vitest's timeout instead of failing,
# and vitest's exit code; exits 0 whatever the tests do, 2 on bad arguments.
set -euo pipefail

usage() { sed -n '2,23p' "$0" >&2; exit 2; }

PKG='' OUT='' CONFIG='' DROP_GLOBAL=0 STUBS=() FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --stub) STUBS+=("$2"); shift 2 ;;
    --config) CONFIG=$2; shift 2 ;;
    --no-global-setup) DROP_GLOBAL=1; shift ;;
    --) shift; FILES=("$@"); break ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$PKG" ] && [ -n "$OUT" ] && [ ${#STUBS[@]} -gt 0 ] && [ ${#FILES[@]} -gt 0 ] || usage
PKG=$(cd "$PKG" && pwd)
mkdir -p "$OUT/stub"
OUT=$(cd "$OUT" && pwd)
if [ -z "$CONFIG" ]; then
  for c in vitest.config.{ts,mts,mjs,js,cts,cjs} vite.config.{ts,mts,mjs,js,cts,cjs}; do
    [ -f "$PKG/$c" ] && { CONFIG=$PKG/$c; break; }
  done
fi
[ -n "$CONFIG" ] && CONFIG=$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")

# The stubs and the config, written by node so that names and paths are quoted right.
PKG="$PKG" OUT="$OUT" CONFIG="$CONFIG" DROP_GLOBAL="$DROP_GLOBAL" node - "${STUBS[@]}" <<'EOF'
const fs = require('node:fs')
const path = require('node:path')
const { PKG, OUT, CONFIG, DROP_GLOBAL } = process.env
const ident = /^[A-Za-z_$][\w$]*$/
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')
const aliases = []
process.argv.slice(2).forEach((arg, i) => {
  const at = arg.indexOf(':')
  if (at < 1) throw new Error(`--stub ${arg}: expected SPEC:EXPORT[,EXPORT...]`)
  const spec = arg.slice(0, at).replace(/^(\.\.?\/)+/, '').replace(/\.[cm]?[jt]sx?$/, '')
  const lines = [
    '// Written by stub_run_vitest.sh: every export throws, so each test fails on its own missing piece.',
    'const missing = (name) => function () { throw new Error(`stub: ${name} is not implemented`) }',
  ]
  for (const part of arg.slice(at + 1).split(',').map((s) => s.trim()).filter(Boolean)) {
    const eq = part.indexOf('=')
    const name = eq < 0 ? part : part.slice(0, eq).trim()
    if (!ident.test(name)) throw new Error(`--stub ${arg}: ${name} is not an export name`)
    const value = eq < 0 ? `missing(${JSON.stringify(name)})` : part.slice(eq + 1).trim()
    lines.push(name === 'default' ? `export default ${value}` : `export const ${name} = ${value}`)
  }
  const file = path.join(OUT, 'stub', `stub-${i + 1}-${path.basename(spec)}.mjs`)
  fs.writeFileSync(file, lines.join('\n') + '\n')
  // Vite replaces the part of the specifier the regex matches: match all of it.
  aliases.push(`{ find: /^(.*\\/)?${esc(spec)}(\\.[cm]?[jt]sx?)?$/, replacement: ${JSON.stringify(file)} }`)
  console.log(`stub: ${spec} -> ${file}`)
})
const config = [
  '// Written by stub_run_vitest.sh: the project\'s config with the missing modules stubbed.',
  CONFIG ? `import loaded from ${JSON.stringify(CONFIG)}` : 'const loaded = {}',
  "const base = (await (typeof loaded === 'function' ? loaded({ command: 'serve', mode: 'test' }) : loaded)) ?? {}",
  'const list = (a) => !a ? [] : Array.isArray(a) ? a : Object.entries(a).map(([find, replacement]) => ({ find, replacement }))',
  'export default {',
  '  ...base,',
  `  root: ${JSON.stringify(PKG)},`,
  `  resolve: { ...base.resolve, alias: [${aliases.join(', ')}, ...list(base.resolve?.alias)] },`,
  `  test: { ...base.test${DROP_GLOBAL === '1' ? ', globalSetup: []' : ''} },`,
  '}',
]
fs.writeFileSync(path.join(OUT, 'stub', 'vitest.config.mjs'), config.join('\n') + '\n')
console.log(`config: ${path.join(OUT, 'stub', 'vitest.config.mjs')} (base: ${CONFIG || 'none'})`)
EOF

set +e
(cd "$PKG" && npx vitest run --config "$OUT/stub/vitest.config.mjs" --reporter=verbose "${FILES[@]}") \
  > "$OUT/stub/output.txt" 2>&1
rc=$?
set -e
# One line per test (passed or failed), then the reason of each failure as vitest prints it.
grep -E '^\s*(✓|×|↓|✗)|^ (FAIL|Error|AssertionError)|Error: ' "$OUT/stub/output.txt" | head -200 || true
# A RED test fails; one that reaches vitest's timeout hangs instead: it waits for something only
# the new code sends. Listed apart, so the review can make it wait for the expected event OR what
# the old code sends.
hung=$(awk '/^ FAIL /{ last = $0 } /Test timed out in/{ print last }' "$OUT/stub/output.txt" | sort -u)
if [ -n "$hung" ]; then
  echo "hangs until the timeout instead of failing ($(wc -l <<< "$hung" | tr -d ' ')):"
  echo "$hung"
fi
echo "vitest exit: $rc (full output: $OUT/stub/output.txt)"
exit 0
