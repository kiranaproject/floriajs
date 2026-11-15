#!/usr/bin/env bash
# Review an upstream Test262 update before changing the pin.
#
#   tools/review_upstream_update.sh <new-revision>          # dry run
#   tools/review_upstream_update.sh <new-revision> --apply  # write the pin
#
# The pinned checkout is never fetched automatically. Run fetch/checkout first
# and make sure the local checkout is at the candidate revision. --apply refuses
# to write unless HEAD matches the candidate.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST262="$(cd "$HERE/.." && pwd)"
ROOT="${TEST262_ROOT:-$TEST262/.upstream}"
PIN="$TEST262/config/test262-revision.txt"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <new-revision> [--apply]" >&2
  exit 2
fi

NEW="$1"
APPLY="false"
if [[ $# -ge 2 && "$2" == "--apply" ]]; then
  APPLY="true"
fi

if [[ ! "$NEW" =~ ^[0-9a-f]{40}$ ]]; then
  echo "new revision must be a full 40-character lowercase SHA-1" >&2
  exit 2
fi
if [[ ! -d "$ROOT/.git" ]]; then
  echo "Test262 checkout missing at $ROOT" >&2
  exit 2
fi
if ! git -C "$ROOT" cat-file -e "$NEW^{commit}" 2>/dev/null; then
  echo "revision $NEW is not present in $ROOT; fetch it before reviewing" >&2
  exit 2
fi

OLD="$(tail -n 1 "$PIN" | tr -d '[:space:]')"
echo "current pin: $OLD"
echo "candidate:   $NEW"
git -C "$ROOT" show -s --format='candidate commit: %H%n  date: %ad%n  subject: %s' --date=iso "$NEW"

echo
echo "Upstream changes in test/, harness/, and package.json:"
git -C "$ROOT" diff --stat "$OLD" "$NEW" -- test harness package.json || true

echo
echo "Review checklist:"
echo "  1. Inspect the changed tests and harness files above."
echo "  2. Check out the candidate and run the smoke corpus."
echo "  3. Run the extended diagnostic with worker parallelism and a deadline."
echo "  4. Regenerate every reviewed baseline and inspect the diff."
echo "  5. Update docs/test262.md with the new revision and any new gaps."
echo "  6. Only then write the pin (rerun with --apply)."

if [[ "$APPLY" != "true" ]]; then
  echo
  echo "Dry run only; the pin was not changed."
  exit 0
fi

HEAD="$(git -C "$ROOT" rev-parse HEAD)"
if [[ "$HEAD" != "$NEW" ]]; then
  echo "--apply requires the checkout HEAD to equal the candidate ($HEAD != $NEW)" >&2
  exit 2
fi

printf '# Pinned upstream revision. Change only with a reviewed baseline update.\n%s\n' "$NEW" > "$PIN"
echo
echo "Updated $PIN to $NEW."
