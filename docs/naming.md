# The name, and the action

The app is **Clover**. The action is **Touch Grass**.

It was called Dad until its first day with a real family, who turned it down
over the name alone. Nothing else was wrong with it. The product is for a whole
household, and a name that put one member in charge of the others was the one
thing the household could not get past. So the joke went, and these words
replaced it.

## Why "touch grass"

It works twice, and the product needs both:

1. **Physically.** You touch your phone to a tag. That is the whole gesture.
2. **The other way.** The point of the gesture is to step away from the screen
   and back into the room you are actually in.

## Why the app is not called "Touch Grass"

At least four App Store screen-time apps were already called it when this was
decided (2026-10), one with thousands of ratings. A name shared with a direct
competitor is lost in search and borrows their trademark risk. So the phrase is
the *action*, and the app has a name of its own.

## Why "Clover"

Clover grows in lawns: it is literally among the grass you would touch. It is
short enough for the space under an icon, it has no surveillance or discipline
in it, it is a plant rather than a person, and a teenager can say it without
wincing. The family chose it.

## The words

| Where | Word | Example |
|---|---|---|
| The action, standing alone | Touch Grass | a button, a Siri shortcut, the widget |
| The action, mid-sentence | touch grass | "Tap your Clover tag to touch grass." |
| The state | Outside / outside | "You're outside." · "Outside · Sleep" · "1h 45m outside" |
| The release | Come Back In / come back in | a button · "tap your tag again to come back in" |
| Just released | Back in | "Back in. 3 emergency overrides left this month." |
| The override | Emergency Exit | the shield's second button |

Nouns:

- **A Clover tag** — the NFC sticker you tap.
- **A Mode** — a named set of apps to take away (Deep Work, Sleep, Gym).
- **A grass streak** — consecutive days with at least one session.

## Copy rules

1. **Capitalise only where it stands alone.** "Touch Grass" is title case as
   the name of something you press, and ordinary lower case inside a sentence.
   It is an English idiom, not a coined word, and capitalising it mid-sentence
   reads as marketing. (The old name was a proper noun doing a verb's job, so
   it was capitalised everywhere and a lint enforced it. That rule is gone.)
2. **Never say it as an order to someone else.** "Go touch grass" is also an
   insult — what you tell somebody who is too online. Said by a parent to a
   teenager, it lands exactly as badly as the old name did. The copy says it
   as something *you* do: "Touch Grass", "You touched grass for Sleep".
   `VocabularyTests` fails if "go touch grass" appears in produced copy.
3. **The shield screen is the important one.** It is the only copy a user
   reads while being told no. A short headline — "You're outside." — then a
   sentence, then a way out.
4. **Never explain the metaphor.** No "(that means your apps are blocked!)".
   It teaches itself the second time someone sees it.

## What did not change, and why

Bundle ids (`app.dad.Dad.*`), the App Group (`group.app.dad.shared`), the
`dad://` link scheme, stored keys and type names (`DadEngine`, `DadMode`) are
still called Dad. Nobody using the app ever sees them. Changing the bundle ids
means a new App Store Connect record, four new App IDs with Family Controls
enabled again, new signing profiles and another round trip with Apple, and
changing the App Group wipes every tester's state. Renaming the *types* is safe
and only a matter of time; it is a separate change.

`scripts/lint-vocabulary.sh` fails if the old name reaches anything a person
reads, from a SwiftUI view or an Info.plist, and is built to leave all of the
identifiers above alone.

All of the copy lives in one file,
[`Dad/Shared/Core/DadVocabulary.swift`](../Dad/Shared/Core/DadVocabulary.swift),
so the app, the shield extension and the Siri phrases can't drift apart.
