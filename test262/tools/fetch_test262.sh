#!/usr/bin/env bash
# Fetch exactly the pinned Test262 revision and only the directories used by
# the reviewed smoke and curated lists. This is a setup helper, not part of the
# runner: tools/run_test262.py never clones, fetches, or rewrites the checkout.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST262="$(cd "$HERE/.." && pwd)"
ROOT="${1:-$TEST262/.upstream}"
REVISION="$(tail -n 1 "$TEST262/config/test262-revision.txt" | tr -d '[:space:]')"

if [[ ! -d "$ROOT/.git" ]]; then
  git clone --filter=blob:none --sparse --quiet https://github.com/tc39/test262.git "$ROOT"
fi

mapfile -t PATTERNS < <(
  python3 - "$TEST262/config/smoke-tests.txt" "$TEST262/config/curated-tests.txt" <<'PY'
from pathlib import PurePosixPath
import sys

patterns = {"/package.json", "/harness/"}
for name in sys.argv[1:]:
    for line in open(name, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parent = PurePosixPath(line).parent.as_posix()
        patterns.add(f"/test/{parent}/")
for pattern in sorted(patterns):
    print(pattern)
PY
)

git -C "$ROOT" sparse-checkout set --no-cone "${PATTERNS[@]}"
git -C "$ROOT" checkout --quiet "$REVISION"

ACTUAL="$(git -C "$ROOT" rev-parse HEAD)"
if [[ "$ACTUAL" != "$REVISION" ]]; then
  echo "Test262 revision mismatch: expected $REVISION, got $ACTUAL" >&2
  exit 2
fi

echo "Test262 $ACTUAL ready at $ROOT"
