#!/usr/bin/env bash
# Build and run the Floria JS benchmark suite.
#
#   bench/run_bench.sh              run everything, print tables
#   bench/run_bench.sh --save       also write bench/baseline.txt
#   bench/run_bench.sh --check      compare against bench/baseline.txt
#
# Results are machine-dependent. The baseline exists to catch a *regression* on
# the same machine, not to compare across machines.
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

echo "Building benchmarks..."
for prog in bench_js bench_ftml; do
  "$FPC" -Mobjfpc -Sh -O2 -FU"$BUILD" \
    -Fu"$REPO/src/main/pascal" -Fu"$HERE" -FE"$BUILD" \
    "$HERE/$prog.pas" >/dev/null
done

OUT="$BUILD/results.tsv"
: > "$OUT"

echo
"$BUILD/bench_js"   --out "$BUILD/js.tsv"
echo
"$BUILD/bench_ftml" --out "$BUILD/ftml.tsv"

# Merge the two result files, skipping the header of the second.
cat "$BUILD/js.tsv" > "$OUT"
tail -n +2 "$BUILD/ftml.tsv" >> "$OUT"

case "$MODE" in
  save)
    cp "$OUT" "$HERE/baseline.txt"
    echo
    echo "Baseline written to bench/baseline.txt"
    ;;
  check)
    if [[ ! -f "$HERE/baseline.txt" ]]; then
      echo "No baseline to compare against; run with --save first." >&2
      exit 1
    fi
    echo
    echo "Comparing against bench/baseline.txt"
    # Compare the us/op column, reporting anything that got slower by >20%.
    awk -F'\t' 'NR==FNR { if (FNR>1) base[$1]=$5; next }
      FNR>1 {
        name=$1; cur=$5;
        if (name in base) {
          b = base[name] + 0;
          c = cur + 0;
          if (b > 0 && c > b * 1.2) {
            printf "  SLOWER  %-30s %.4f -> %.4f us/op (+%.1f%%)\n", name, b, c, (c-b)/b*100;
            bad=1
          }
        }
      }
      END { if (!bad) print "  no regressions over 20%" }' "$HERE/baseline.txt" "$OUT"
    ;;
esac
