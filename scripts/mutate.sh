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

# Compile FIRST, and decide "did not build" on the compiler alone.
#
# The obvious version runs `swift test` and calls it a build failure when the
# output has no "Executed N tests" line. That is wrong for a third outcome
# nobody thought about: a mutation that compiles and then **crashes** the test
# binary before any test runs — a trap in a stored property's initialiser, say,
# which takes the whole class down during static setup. No "Executed" line is
# printed, so a perfectly valid mutation that the suite caught in the loudest
# way possible was reported as invalid Swift.
#
# That misreport is not free: an adversarial review discarded three verdicts
# because of it, and a discarded verdict looks exactly like a covered one.
if ! swift build --build-tests >/dev/null 2>&1; then
  echo "  ?  DID NOT BUILD — $LABEL (not a surviving mutant; the mutation is invalid Swift)"
  exit 1
fi

OUTPUT="$(swift test 2>&1)"
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  # Includes a crash. A mutation that makes the suite trap is caught by it —
  # noisily, but caught.
  if grep -q "Executed .* tests" <<<"$OUTPUT"; then
    echo "  ✔  caught    — $LABEL"
  else
    echo "  ✔  caught    — $LABEL (the suite crashed before finishing; still caught)"
  fi
else
  echo "  ✘  SURVIVED  — $LABEL. The suite does not cover this."
fi
