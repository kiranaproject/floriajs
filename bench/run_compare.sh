#!/usr/bin/env bash
# Compare floriajs against Node on the same machine, using the same .js files.
#
#   bench/run_compare.sh            print the comparison
#   bench/run_compare.sh --save     also write bench/compare-baseline.txt
#   bench/run_compare.sh --check    fail if any ratio regresses by >25%
#
# Why a ratio: absolute microseconds depend on the machine, so a baseline taken
# on one laptop says nothing about another. The ratio against Node does not —
# both interpreters run on the same hardware, so the ratio travels.
set -euo pipefail

FPC="${FPC:-/home/afumi/fpcup/files/fpc/bin/x86_64-linux/fpc}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

MODE="run"
for arg in "$@"; do
  case "$arg" in
    --save)  MODE="save" ;;
    --check) MODE="check" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# --- Build the library from local source into the runner's unit directory.
#
# The runner declares a dependency on floriajs, which Pasbuild resolves to the
# installed copy in ~/.pasbuild/repository. That copy can be stale, and a stale
# copy would silently benchmark old code: an earlier run reported generators as
# unimplemented because the installed units predated them. Compiling the library
# into the runner's target/units first shadows the installed copy, because that
# directory is searched before the repository.
echo "Building library into the runner's unit directory..."
mkdir -p "$HERE/runner/target/units"
"$FPC" -Mobjfpc -Sh -O2 \
  -FU"$HERE/runner/target/units" -Fu"$REPO/src/main/pascal" \
  -FE"$HERE/runner/target/units" \
  "$REPO/src/main/pascal/floriajs.pas" >/dev/null

echo "Building the runner (Pasbuild sub-project)..."
(cd "$HERE/runner" && pasbuild compile >/dev/null)

RUNNER="$HERE/runner/target/floria-bench-runner"
if [[ ! -x "$RUNNER" ]]; then
  echo "runner did not build" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node not found; install Node.js to run the comparison" >&2
  exit 1
fi

# --- Run each workload under both engines, alternating the order.
#
# Running all of one engine's workloads and then all of the other's biases the
# result: whichever runs first pays for CPU frequency ramp-up, and an early
# version of this script showed every ratio growing by about 12% between two
# runs for that reason. Alternating per workload, and alternating which engine
# goes first, cancels the bias in both directions.
echo "Running workloads under floriajs and Node..."
: > "$BUILD/floria.tsv"
: > "$BUILD/node.tsv"
echo -e 'name\truns\ttotal_us\tper_run_us\tresult' >> "$BUILD/floria.tsv"
echo -e 'name\truns\ttotal_us\tper_run_us\tresult' >> "$BUILD/node.tsv"

order=0
for wf in $(find "$HERE/workloads" -name '*.js' | sort); do
  order=$(( (order + 1) % 2 ))
  if [[ $order -eq 0 ]]; then
    "$RUNNER" "$wf" | tail -n +2 >> "$BUILD/floria.tsv"
    node "$HERE/node/run_node.js" --file "$wf" | tail -n +2 >> "$BUILD/node.tsv"
  else
    node "$HERE/node/run_node.js" --file "$wf" | tail -n +2 >> "$BUILD/node.tsv"
    "$RUNNER" "$wf" | tail -n +2 >> "$BUILD/floria.tsv"
  fi
done

# --- Compare. The ratio is floriajs microseconds divided by Node microseconds,
# so a larger number is slower. Results are checked for agreement first: a
# comparison of two interpreters that computed different answers is meaningless.
# Mismatches are written to a separate file rather than to /dev/stderr, which
# awk does not always honour, and reported below so they cannot be missed.
awk -F'\t' -v OFS='\t' -v mismatchFile="$BUILD/mismatch.txt" '
  NR == FNR {
    if (FNR > 1) { floria[$1] = $4; floriaResult[$1] = $5 }
    next
  }
  FNR == 1 { next }
  {
    name = $1;
    nodeUs = $4;
    nodeResult = $5;
    if (!(name in floria)) next;
    if (floriaResult[name] != nodeResult) {
      printf "%s floria=%s node=%s\n", name, floriaResult[name], nodeResult >> mismatchFile;
      mismatched++;
    }
    ratio = (nodeUs + 0) > 0 ? floria[name] / nodeUs : 0;
    printf "%s\t%s\t%s\t%.1f\t%s\n", name, floria[name], nodeUs, ratio, nodeResult
  }
  END {
    if (mismatched > 0) {
      printf "\nERROR: %d workload(s) produced different results under the two engines:\n", mismatched;
      while ((getline line < mismatchFile) > 0) printf "  %s\n", line;
      printf "The timings are not comparable.\n";
      exit 1;
    }
  }
' "$BUILD/floria.tsv" "$BUILD/node.tsv" > "$BUILD/compare.tsv" || {
  # awk wrote its mismatch report into compare.tsv before exiting; show it.
  cat "$BUILD/compare.tsv"
  exit 1
}

{
  echo
  printf '%-20s %12s %12s %10s\n' 'workload' 'floriajs us' 'node us' 'ratio'
  printf '%-20s %12s %12s %10s\n' '--------------------' '------------' '------------' '----------'
  awk -F'\t' '{ printf "%-20s %12s %12s %9sx\n", $1, $2, $3, $4 }' "$BUILD/compare.tsv"
  echo
  awk -F'\t' '
    { sumLog += log($4); sum += $4; n++; if ($4 > worst) { worst = $4; worstName = $1 } }
    END {
      if (n > 0) printf "geometric-mean ratio: %.1fx   slowest: %s (%.1fx)\n",
        exp(sumLog / n), worstName, worst
    }' "$BUILD/compare.tsv"
}

case "$MODE" in
  save)
    cp "$BUILD/compare.tsv" "$HERE/compare-baseline.txt"
    echo
    echo "Baseline written to bench/compare-baseline.txt"
    ;;
  check)
    if [[ ! -f "$HERE/compare-baseline.txt" ]]; then
      echo "No baseline; run with --save first." >&2
      exit 1
    fi
    echo
    echo "Comparing ratios against bench/compare-baseline.txt"
    awk -F'\t' '
      NR == FNR { if (FNR > 0) base[$1] = $4; next }
      {
        if ($1 in base) {
          b = base[$1] + 0; c = $4 + 0;
          if (b > 0 && c > b * 1.25) {
            printf "  SLOWER  %-20s %sx -> %sx (+%.1f%%)\n", $1, b, c, (c - b) / b * 100;
            bad = 1;
          }
        }
      }
      END { if (!bad) print "  no ratio regressions over 25%" }
    ' "$HERE/compare-baseline.txt" "$BUILD/compare.tsv"
    ;;
esac
