#!/usr/bin/env bash
# Run one mutation against the suite, and restore.
#
#   scripts/mutate.sh <file> <old text> <new text> "<label>"
#
# Decides by swift test's EXIT CODE, never by parsing its prose. The obvious
# version greps for "with N failures" and is wrong: XCTest prints "with 1
# failure", singular, so every mutation caught by exactly one test — which is
# most precisely-targeted ones — gets reported as surviving. That misdiagnosis
# cost three separate re-verifications in this repo before it was spotted.
#
# It also distinguishes a build failure from a passing suite. A mutation that
# doesn't compile is not a surviving mutant, and must not be reported as one.
set -uo pipefail
cd "$(dirname "$0")/.."

FILE="$1"; OLD="$2"; NEW="$3"; LABEL="${4:-mutation}"
BACKUP="$(mktemp)"
cp "$FILE" "$BACKUP"
trap 'cp "$BACKUP" "$FILE"; rm -f "$BACKUP"' EXIT

if ! python3 - "$FILE" "$OLD" "$NEW" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
if old not in s:
    sys.exit(1)
open(path, "w").write(s.replace(old, new, 1))
PY
then
  echo "  ?  NOT APPLIED — $LABEL (text not found in $FILE)"
  exit 1
fi

OUTPUT="$(swift test 2>&1)"
STATUS=$?

if ! grep -q "Executed .* tests" <<<"$OUTPUT"; then
  echo "  ?  DID NOT BUILD — $LABEL (not a surviving mutant; the mutation is invalid Swift)"
  exit 1
fi

if [ "$STATUS" -ne 0 ]; then
  echo "  ✔  caught    — $LABEL"
else
  echo "  ✘  SURVIVED  — $LABEL. The suite does not cover this."
fi
