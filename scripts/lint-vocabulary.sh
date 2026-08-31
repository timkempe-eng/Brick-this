#!/usr/bin/env bash
# The verb is the product. docs/naming.md says capital T throughout, including
# mid-sentence — "Tim your phone", never "tim your phone". Lowercasing it makes
# the whole conceit read like a typo, and it had crept into eight call sites
# before this check existed.
#
# `modeNoun` is exempt: "mode" is an ordinary common noun.
set -uo pipefail
cd "$(dirname "$0")/.."

hits=$(grep -rn "Vocab\.\(verb\|verbThirdPerson\|verbPast\|verbGerund\|unVerb\|unVerbPast\|appName\|tagNoun\|sessionNoun\|streakNoun\)\.lowercased()" Tim/ || true)

if [ -n "$hits" ]; then
  echo "Vocabulary lint failed — these lowercase a proper form of the verb:"
  echo "$hits"
  echo
  echo "See docs/naming.md. Use the form as declared, or add a new one to Vocab."
  exit 1
fi
echo "Vocabulary lint passed."
