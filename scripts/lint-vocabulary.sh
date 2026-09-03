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
# `modeNoun` is the ONLY exemption: "mode" is an ordinary common noun.
#
# There were three. The other two — `dadAction` and `emergencyUnDad` — were
# added on the theory that they were common nouns, and they are not: they
# expand to "Dad my phone" and "Emergency Un-Dad", so lowercasing them produces
# "dad my phone", the literal example in hard rule 4. A review confirmed the
# lint passed with both spelled out in a shipping file. Neither had a call
# site; they were exempted for nothing and would have permitted the one thing
# this script exists to stop. **Add an exemption only for a symbol that
# contains no form of the verb, and check by expanding it.**
#
# The match also covers a function call and the two other ways Swift lowercases
# a string, because the interpolating helpers — `warning`, `asking` — are where
# the verb most often ends up mid-sentence, and they were entirely unwatched.
set -uo pipefail
cd "$(dirname "$0")/.."

EXEMPT="modeNoun"

hits=$(grep -rnoE "Vocab\.[A-Za-z]+(\([^)]*\))?\.(lowercased\(|localizedLowercase)" Dad/ \
       | grep -vE "Vocab\.($EXEMPT)\.lowercased\(" || true)

if [ -n "$hits" ]; then
  echo "Vocabulary lint failed — these lowercase a proper form of the verb:"
  echo "$hits"
  echo
  echo "See docs/naming.md. Use the form as declared, add a new one to Vocab,"
  echo "or add it to EXEMPT in this script if it really is a common noun."
  exit 1
fi
echo "Vocabulary lint passed."
