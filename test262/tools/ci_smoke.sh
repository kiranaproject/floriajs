#!/usr/bin/env bash
# Deterministic CI entrypoint for the reviewed Test262 corpus.
#
# The upstream checkout is explicit and revision-pinned; this script never
# fetches a moving branch. A semantic failure is expected in the reviewed
# baseline, but a regression, timeout, crash, or harness error fails the job.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST262="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$TEST262/.." && pwd)"
ROOT="${TEST262_ROOT:-${1:-$TEST262/.upstream}}"
HOST="$TEST262/target/floria-test262-host"
RESULTS="$TEST262/results/ci"
JOBS="${TEST262_JOBS:-1}"
MAX_DURATION="${TEST262_MAX_DURATION:-0}"

if [[ ! -d "$ROOT/test" || ! -d "$ROOT/harness" ]]; then
  echo "Test262 checkout missing at $ROOT; fetching the pinned revision." >&2
  bash "$TEST262/tools/fetch_test262.sh" "$ROOT"
fi

if command -v pasbuild >/dev/null 2>&1; then
  (cd "$TEST262" && pasbuild compile >/dev/null)
else
  mkdir -p "$TEST262/target/ci-units"
  fpc -Mobjfpc -Sh \
    "-Fu$TEST262/src/main/pascal" \
    "-Fu$REPO/src/main/pascal" \
    "-FU$TEST262/target/ci-units" \
    "-o$HOST" \
    "$TEST262/src/main/pascal/floria.test262.host.pas"
fi

if [[ ! -x "$HOST" ]]; then
  echo "host executable was not produced: $HOST" >&2
  exit 2
fi

mkdir -p "$RESULTS"

echo "== Adapter fixtures =="
python3 "$TEST262/tools/run_host_smoke.py" >/dev/null
python3 "$TEST262/tools/run_metadata_smoke.py" >/dev/null
python3 "$TEST262/tools/run_negative_smoke.py" >/dev/null
python3 "$TEST262/tools/run_report_smoke.py" >/dev/null
python3 "$TEST262/tools/run_async_smoke.py" >/dev/null
python3 "$TEST262/tools/run_module_smoke.py" >/dev/null

echo "== Reviewed upstream smoke corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/smoke-tests.txt" \
  --report "$RESULTS/smoke-report.json" \
  --output "$RESULTS/smoke.jsonl" \
  --baseline "$TEST262/baselines/phase10-smoke.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream with-statement corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/with-tests.txt" \
  --report "$RESULTS/with-report.json" \
  --output "$RESULTS/with.jsonl" \
  --baseline "$TEST262/baselines/phase10-with.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream reserved-word corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/reserved-word-tests.txt" \
  --report "$RESULTS/reserved-word-report.json" \
  --output "$RESULTS/reserved-word.jsonl" \
  --baseline "$TEST262/baselines/phase10-reserved-words.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream Proxy invariant corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/proxy-invariant-tests.txt" \
  --report "$RESULTS/proxy-invariant-report.json" \
  --output "$RESULTS/proxy-invariant.jsonl" \
  --baseline "$TEST262/baselines/phase10-proxy-invariants.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream import-attributes corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/import-attributes-tests.txt" \
  --report "$RESULTS/import-attributes-report.json" \
  --output "$RESULTS/import-attributes.jsonl" \
  --baseline "$TEST262/baselines/phase10-import-attributes.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream BigInt Atomics corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/bigint-atomics-tests.txt" \
  --report "$RESULTS/bigint-atomics-report.json" \
  --output "$RESULTS/bigint-atomics.jsonl" \
  --baseline "$TEST262/baselines/phase10-bigint-atomics.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream strict-escape corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/strict-escape-tests.txt" \
  --report "$RESULTS/strict-escape-report.json" \
  --output "$RESULTS/strict-escape.jsonl" \
  --baseline "$TEST262/baselines/phase10-strict-escapes.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream agent corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/agent-tests.txt" \
  --report "$RESULTS/agent-report.json" \
  --output "$RESULTS/agent.jsonl" \
  --baseline "$TEST262/baselines/phase10-agents.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream Proxy corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/proxy-tests.txt" \
  --report "$RESULTS/proxy-report.json" \
  --output "$RESULTS/proxy.jsonl" \
  --baseline "$TEST262/baselines/phase10-proxy.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream SharedArrayBuffer/Atomics corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/atomics-tests.txt" \
  --report "$RESULTS/atomics-report.json" \
  --output "$RESULTS/atomics.jsonl" \
  --baseline "$TEST262/baselines/phase10-atomics.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream module-cycle corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/module-cycle-tests.txt" \
  --report "$RESULTS/module-cycle-report.json" \
  --output "$RESULTS/module-cycle.jsonl" \
  --baseline "$TEST262/baselines/phase10-module-cycles.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream strict early-error corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/strict-early-errors-tests.txt" \
  --report "$RESULTS/strict-early-errors-report.json" \
  --output "$RESULTS/strict-early-errors.jsonl" \
  --baseline "$TEST262/baselines/phase10-strict-early-errors.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream Symbol.toPrimitive corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/to-primitive-tests.txt" \
  --report "$RESULTS/to-primitive-report.json" \
  --output "$RESULTS/to-primitive.jsonl" \
  --baseline "$TEST262/baselines/phase10-to-primitive.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream async-generator corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/async-generator-tests.txt" \
  --report "$RESULTS/async-generator-report.json" \
  --output "$RESULTS/async-generator.jsonl" \
  --baseline "$TEST262/baselines/phase10-async-generators.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream realm corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/realm-tests.txt" \
  --report "$RESULTS/realm-report.json" \
  --output "$RESULTS/realm.jsonl" \
  --baseline "$TEST262/baselines/phase10-realms.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream library-gaps corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/library-gaps-tests.txt" \
  --report "$RESULTS/library-gaps-report.json" \
  --output "$RESULTS/library-gaps.jsonl" \
  --baseline "$TEST262/baselines/phase10-library-gaps.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream coercion corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 180 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/coercion-tests.txt" \
  --report "$RESULTS/coercion-report.json" \
  --output "$RESULTS/coercion.jsonl" \
  --baseline "$TEST262/baselines/phase10-coercion.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream modern-builtins corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 10 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/modern-builtins-tests.txt" \
  --report "$RESULTS/modern-builtins-report.json" \
  --output "$RESULTS/modern-builtins.jsonl" \
  --baseline "$TEST262/baselines/phase10-modern-builtins.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream function-tostring corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 10 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/function-tostring-tests.txt" \
  --report "$RESULTS/function-tostring-report.json" \
  --output "$RESULTS/function-tostring.jsonl" \
  --baseline "$TEST262/baselines/phase10-function-tostring.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream prototype-constructor corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 10 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/prototype-constructor-tests.txt" \
  --report "$RESULTS/prototype-constructor-report.json" \
  --output "$RESULTS/prototype-constructor.jsonl" \
  --baseline "$TEST262/baselines/phase10-prototype-constructor.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream weak-collections corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 10 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/weak-collections-tests.txt" \
  --report "$RESULTS/weak-collections-report.json" \
  --output "$RESULTS/weak-collections.jsonl" \
  --baseline "$TEST262/baselines/phase10-weak-collections.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream module-record corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 10 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/module-record-tests.txt" \
  --report "$RESULTS/module-record-report.json" \
  --output "$RESULTS/module-record.jsonl" \
  --baseline "$TEST262/baselines/phase10-module-records.json" \
  --fail-on-regression >/dev/null

echo "== Reviewed upstream curated corpus =="
python3 "$TEST262/tools/run_test262.py" \
  --root "$ROOT" \
  --host "$HOST" \
  --timeout 5 \
  --jobs "$JOBS" \
  --max-duration "$MAX_DURATION" \
  --list "$TEST262/config/curated-tests.txt" \
  --report "$RESULTS/curated-report.json" \
  --output "$RESULTS/curated.jsonl" \
  --baseline "$TEST262/baselines/phase10-curated.json" \
  --fail-on-regression >/dev/null

python3 "$TEST262/tools/results.py" markdown \
  "$RESULTS/curated-report.json" \
  "$RESULTS/curated-summary.md"
echo "Markdown summary: $RESULTS/curated-summary.md"

echo "Test262 CI smoke passed."
