#!/usr/bin/env bash
# The verb is the product. docs/naming.md says capital T throughout, including
# mid-sentence — "Dad your phone", never "dad your phone". Lowercasing it makes
# the whole conceit read like a typo, and it had crept into eight call sites
# before this check existed.
#
# The list below is the EXEMPTIONS, not the targets, and that inversion is the
# fix for a hole a review found. Naming the forbidden symbols meant a new one
# was unwatched the moment it was added: `verbsThirdPerson` was declared as an
# alias of `verbThirdPerson`, its own comment claimed the lint covered it, and
# it did not. Anything on `Vocab` is now suspect unless it is listed here, so
# adding a symbol makes the check stricter rather than blinder.
#
# `modeNoun` is exempt: "mode" is an ordinary common noun. So are the two
# capability nouns, which are read out mid-sentence.
set -uo pipefail
cd "$(dirname "$0")/.."

EXEMPT="modeNoun\|emergencyUnDad\|dadAction"

hits=$(grep -rno "Vocab\.[A-Za-z]*\.lowercased()" Dad/ \
       | grep -v "Vocab\.\($EXEMPT\)\.lowercased()" || true)

if [ -n "$hits" ]; then
  echo "Vocabulary lint failed — these lowercase a proper form of the verb:"
  echo "$hits"
  echo
  echo "See docs/naming.md. Use the form as declared, add a new one to Vocab,"
  echo "or add it to EXEMPT in this script if it really is a common noun."
  exit 1
fi
echo "Vocabulary lint passed."
