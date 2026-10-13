#!/usr/bin/env bash
# The app was called Dad, and a family turned it down over the name alone. It
# is Clover now, and its action is Touch Grass — docs/naming.md. This fails if
# the old name reaches anything a person reads.
#
# The unit tests already check every line `Vocab` produces. They cannot see the
# rest: SwiftUI views, App Intents and the Info.plists are not compiled on
# Linux, and those hold most of the app's sentences. So this reads the source.
#
# What counts as the old name: Dad, Dads, Dadded, Dadding and Un-Dad as whole
# words. Code identifiers survive on purpose (`DadMode`, `.dadded`, the
# `app.dad.*` bundle ids and the `group.app.dad.shared` App Group — changing
# those costs Apple round trips and testers' data for nothing a person sees),
# and a whole-word, case-sensitive match leaves every one of them alone.
#
# Comment lines are skipped: what a comment says about history is not copy.
# A trailing `//` comment after code is stripped first, but only when the
# slashes follow a space, so a "https://" inside a string is still checked.
set -uo pipefail
cd "$(dirname "$0")/.."

OLD='\b(Dad|Dads|Dadded|Dadding|Un-Dad|Un-Dadded)\b'

swift_hits=$(grep -rnP --include='*.swift' '' Dad/ \
  | grep -vP '^[^:]+:\d+:\s*(//|\*)' \
  | sed -E 's# //.*$##' \
  | grep -P "^[^:]+:\d+:.*$OLD" || true)

plist_hits=$(grep -rnP --include='*.plist' "<string>[^<]*$OLD[^<]*</string>" Dad/ \
  | grep -v 'app\.dad\.' || true)

hits=$(printf '%s\n%s' "$swift_hits" "$plist_hits" | sed '/^$/d')
if [ -n "$hits" ]; then
  echo "Vocabulary lint failed — the old name is still in copy a person reads:"
  echo "$hits"
  echo
  echo "See docs/naming.md. Use Vocab.appName, Vocab.action, Vocab.state or"
  echo "Vocab.release rather than writing a word out."
  exit 1
fi
echo "Vocabulary lint passed."
