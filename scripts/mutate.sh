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
# Three outcomes, not two. A mutation can compile and then CRASH the test
# binary before any test runs — a trap in a stored property's initialiser takes
# the whole class down during static setup — and that prints no "Executed N
# tests" line either. The old check called that invalid Swift, so a mutation
# the suite had caught in the loudest way available was reported as not a
# mutant at all. A review discarded three verdicts because of it, and a
# discarded verdict looks exactly like a covered one. Compile first, and let
# the compiler alone decide "did not build".
#
# Mutations are applied to CODE, never to a comment, and the line is printed.
# This codebase argues with itself in prose: a guard is usually preceded by a
# paragraph quoting that guard. Replacing the first occurrence in the file puts
# the change in the paragraph, where it does nothing, and the pass is then
# reported as "SURVIVED. The suite does not cover this." A review followed
# exactly that false trail. Skipping comment lines closes it; printing the line
# makes a wrong target visible rather than something to be inferred.
set -uo pipefail
cd "$(dirname "$0")/.."

FILE="$1"; OLD="$2"; NEW="$3"; LABEL="${4:-mutation}"
BACKUP="$(mktemp)"
cp "$FILE" "$BACKUP" || { echo "  ?  NOT APPLIED — $LABEL (cannot read $FILE)"; exit 1; }
trap 'cp "$BACKUP" "$FILE"; rm -f "$BACKUP"' EXIT

APPLIED=$(python3 scripts/_mutate_apply.py "$FILE" "$OLD" "$NEW")
if [ -z "$APPLIED" ]; then
  echo "  ?  NOT APPLIED — $LABEL (no code line in $FILE contains that text)"
  exit 1
fi

if ! swift build --build-tests >/dev/null 2>&1; then
  echo "  ?  DID NOT BUILD — $LABEL [line $APPLIED] (not a surviving mutant; the mutation is invalid Swift)"
  exit 1
fi

OUTPUT="$(swift test 2>&1)"
STATUS=$?

if [ "$STATUS" -ge 128 ] && ! grep -q "Executed .* tests" <<<"$OUTPUT"; then
  # Killed by a signal with no tests reported: OOM, a kill, a runner dying.
  # Infrastructure, not a verdict — and it must not read as one.
  echo "  ?  NO VERDICT — $LABEL [line $APPLIED] (the run died on signal $((STATUS - 128)); re-run it)"
  exit 1
fi

if [ "$STATUS" -ne 0 ]; then
  if grep -q "Executed .* tests" <<<"$OUTPUT"; then
    echo "  ✔  caught    — $LABEL [line $APPLIED]"
  else
    echo "  ✔  caught    — $LABEL [line $APPLIED] (the suite trapped before finishing; still caught)"
  fi
else
  echo "  ✘  SURVIVED  — $LABEL [line $APPLIED]. The suite does not cover this."
fi
