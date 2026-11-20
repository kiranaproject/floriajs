#!/usr/bin/env bash
# Extended, longer-running diagnostic job.
#
# This is deliberately separate from ci_smoke.sh. It runs the same reviewed
# corpora with a larger per-scenario timeout, bounded worker parallelism, an
# optional global deadline, and Markdown summaries. Use it for scheduled or
# manually dispatched jobs, not as the fast pull-request gate.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST262="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$TEST262/.." && pwd)"
ROOT="${TEST262_ROOT:-${1:-$TEST262/.upstream}}"
HOST="$TEST262/target/floria-test262-host"
RESULTS="$TEST262/results/extended"
JOBS="${TEST262_JOBS:-4}"
TIMEOUT="${TEST262_TIMEOUT:-10}"
MAX_DURATION="${TEST262_MAX_DURATION:-3600}"
START_TIME="$(date +%s)"

if [[ ! -d "$ROOT/test" || ! -d "$ROOT/harness" ]]; then
  echo "Test262 checkout missing at $ROOT; fetching the pinned revision." >&2
  bash "$TEST262/tools/fetch_test262.sh" "$ROOT"
fi

if command -v pasbuild >/dev/null 2>&1; then
  (cd "$TEST262" && pasbuild compile >/dev/null)
else
  mkdir -p "$TEST262/target/extended-units"
  fpc -Mobjfpc -Sh \
    "-Fu$TEST262/src/main/pascal" \
    "-Fu$REPO/src/main/pascal" \
    "-FU$TEST262/target/extended-units" \
    "-o$HOST" \
    "$TEST262/src/main/pascal/floria.test262.host.pas"
fi

mkdir -p "$RESULTS"

echo "== Adapter fixtures =="
python3 "$TEST262/tools/run_host_smoke.py" >/dev/null
python3 "$TEST262/tools/run_metadata_smoke.py" >/dev/null
python3 "$TEST262/tools/run_negative_smoke.py" >/dev/null
python3 "$TEST262/tools/run_report_smoke.py" >/dev/null
python3 "$TEST262/tools/run_async_smoke.py" >/dev/null
python3 "$TEST262/tools/run_module_smoke.py" >/dev/null

CORPORA=(
  "smoke|smoke-tests|phase10-smoke"
  "with|with-tests|phase10-with"
  "reserved-word|reserved-word-tests|phase10-reserved-words"
  "proxy-invariant|proxy-invariant-tests|phase10-proxy-invariants"
  "import-attributes|import-attributes-tests|phase10-import-attributes"
  "bigint-atomics|bigint-atomics-tests|phase10-bigint-atomics"
  "strict-escape|strict-escape-tests|phase10-strict-escapes"
  "agent|agent-tests|phase10-agents"
  "proxy|proxy-tests|phase10-proxy"
  "atomics|atomics-tests|phase10-atomics"
  "module-cycle|module-cycle-tests|phase10-module-cycles"
  "strict-early-errors|strict-early-errors-tests|phase10-strict-early-errors"
  "to-primitive|to-primitive-tests|phase10-to-primitive"
  "async-generator|async-generator-tests|phase10-async-generators"
  "realm|realm-tests|phase10-realms"
  "library-gaps|library-gaps-tests|phase10-library-gaps"
  "coercion|coercion-tests|phase10-coercion|180"
  "modern-builtins|modern-builtins-tests|phase10-modern-builtins|10"
  "function-tostring|function-tostring-tests|phase10-function-tostring|10"
  "prototype-constructor|prototype-constructor-tests|phase10-prototype-constructor|10"
  "weak-collections|weak-collections-tests|phase10-weak-collections|10"
  "module-record|module-record-tests|phase10-module-records|10"
  "curated|curated-tests|phase10-curated"
)

printf '# Extended Test262 diagnostic\n\n' > "$RESULTS/summary.md"
printf 'Generated: `%s`\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RESULTS/summary.md"

for entry in "${CORPORA[@]}"; do
  IFS='|' read -r name list baseline corpus_timeout <<< "$entry"
  if [[ -z "${corpus_timeout:-}" ]]; then
    corpus_timeout="$TIMEOUT"
  fi
  NOW="$(date +%s)"
  REMAINING=$((MAX_DURATION - (NOW - START_TIME)))
  if (( REMAINING <= 0 )); then
    echo "global extended-diagnostic deadline of ${MAX_DURATION}s was reached" >&2
    exit 2
  fi
  echo "== Extended corpus: $name (remaining budget: ${REMAINING}s) =="
  python3 "$TEST262/tools/run_test262.py" \
    --root "$ROOT" \
    --host "$HOST" \
    --timeout "$corpus_timeout" \
    --jobs "$JOBS" \
    --max-duration "$REMAINING" \
    --list "$TEST262/config/$list.txt" \
    --report "$RESULTS/$name-report.json" \
    --output "$RESULTS/$name.jsonl" \
    --baseline "$TEST262/baselines/$baseline.json" \
    --fail-on-regression >/dev/null

  python3 "$TEST262/tools/results.py" markdown \
    "$RESULTS/$name-report.json" \
    "$RESULTS/$name-summary.md"
  {
    printf '## %s\n\n' "$name"
    sed '1d' "$RESULTS/$name-summary.md"
    printf '\n'
  } >> "$RESULTS/summary.md"
done

echo "Extended Test262 diagnostic passed. Summary: $RESULTS/summary.md"
