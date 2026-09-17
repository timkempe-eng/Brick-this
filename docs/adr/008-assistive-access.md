# ADR 008: Assistive Access is a place Dad runs, not a profile Dad can switch

**Status:** accepted
**Date:** 2026-09-17

## Context

The request: tap the tag, and the phone switches into a profile set up in
Assistive Access — iOS's mode that reduces the whole phone to a few large
buttons, chosen apps and plain sentences. It is the most Dad-shaped feature
Apple ships, and it is a fair thing to want: it is the only place on iOS where
a phone visibly *becomes* something simpler, rather than merely losing apps.

## The constraint

**Nothing in the public API enters, leaves, or configures Assistive Access.**
Everything Apple documents for third-party apps is the five symbols below, and
every one of them reads the mode or draws inside it:

| Symbol | Since | What it does |
|---|---|---|
| `AssistiveAccess` (SwiftUI scene) | iOS 26 | Draws *your app* while the mode is already on |
| `UISupportsAssistiveAccess` | iOS 26 | Declares that your app has such a scene |
| `UISupportsFullScreenInAssistiveAccess` | iOS 17 | Lets your standard UI use the full frame |
| `AccessibilitySettings.isAssistiveAccessEnabled` | iOS 18 | Reads whether the mode is on |
| `EnvironmentValues.accessibilityAssistiveAccessEnabled` | iOS 18 | The same, in SwiftUI |

Apple's own documentation is explicit about who does the switching: "A trusted
supporter, such as a family member or caregiver, sets up this feature in
Settings > Accessibility > Assistive Access. They choose the system and
third-party apps to make available."

Re-runnable, and the check that would notice Apple changing its mind:

```bash
curl -s https://developer.apple.com/tutorials/data/documentation/accessibility/assistive-access.json \
  | python3 -c 'import json,sys; print([i.split("/")[-1] for s in json.load(sys.stdin)["topicSections"] for i in s["identifiers"]])'
```

Two further facts from the user guide, both load-bearing:

- **Entering needs Settings or the Accessibility Shortcut, and the Assistive
  Access passcode.** Exiting needs a triple-click and the same passcode.
- **There is one configuration, not a set of named profiles.** There is nothing
  to switch *between*, even by hand.

## Why that is fatal for the literal feature

A Dad tap has to work with the phone in a pocket and the app closed — that is
the whole product. Two of the three tap paths run with no foreground at all:

| Path | Process | Could prompt for a passcode |
|---|---|---|
| Shortcuts NFC automation → `ToggleDadIntent` | background | No |
| Background tag reading → universal link | app, cold | Would have to, every tap |
| The in-app button | foreground | Would have to, every tap |

Even granting an API that does not exist, the passcode is not incidental to
Assistive Access — it is the mechanism. The mode is designed so the person
using the phone cannot leave it alone, which is exactly why it cannot be
entered by a sticker on a coaster. Read the other way round: an app that could
push a phone into Assistive Access could take somebody's phone away from them
without their consent. Dad is a boundary the household agrees to, not one it
can be put behind, so this is a capability the product would decline on its own
terms even if it were offered.

## What people are asking for that already exists

The part of the idea that is buildable is built, and has been since allowlist
Modes: **a Mode can name the only things that stay** rather than the things
that go. Sleep that leaves Phone, Messages and Clock is the same shape as an
Assistive Access app list, arrives on a tap, needs no passcode, and releases on
a tap. It is a profile in every sense the tag can honour.

## Decision

Support Assistive Access as a **place Dad runs**, not a state Dad sets.

`AssistiveAccessScreen` in Core decides what a phone in that mode shows — one
sentence, one line naming the Mode, and at most one button — and `DadApp`
declares the `AssistiveAccess` scene that draws it. A household that runs a
phone in Assistive Access can now put Dad on it and have it make sense: the
tag still works, the shields still hold, and the screen has nothing on it to
get lost in.

The one button is the emergency override the shield already carries, under the
same permission and the same rolling allowance. It is on this screen because a
person in Assistive Access may have no way to reach a shielded app to find the
shield's copy of it, which would turn a tag in another room from a friction
into a trap. It widens nothing: same hatch, same five, reachable.

`UISupportsAssistiveAccess` is declared and
`UISupportsFullScreenInAssistiveAccess` is not. They are alternatives — one
streamlines, the other gives the standard UI more room — and the streamlined
one is the one this app actually ships. Below iOS 26 neither the key nor the
scene exists, and Dad renders its standard UI in the reduced frame the system
gives it, exactly as it does today.

## Consequences

The tag cannot change what Assistive Access shows, and no future version of
this app can promise that without Apple shipping an API that does not exist.
Said plainly in the README rather than left as an absence, because it is the
kind of gap a reader assumes is an oversight.

**Not yet proven on a phone.** Two things need a device running Assistive
Access with Dad among its chosen apps: that the streamlined scene is what
appears, and that Screen Time shields keep applying inside the mode (Apple's
settings guide says schedules and limits can be set while it is active, which
is strong but is not the same as watching a shield hold). Both are in
`PARKING_LOT.md` under what needs a phone.

Revisit if Apple ships an API to enter, leave or select an Assistive Access
configuration — at which point the question is not whether it can be built but
whether a phone should be able to put itself somewhere its owner needs a
passcode to leave.

## Sources

[Apple: Assistive Access (developer)](https://developer.apple.com/documentation/accessibility/assistive-access) ·
[Apple: `AssistiveAccess` scene](https://developer.apple.com/documentation/swiftui/assistiveaccess) ·
[Apple: optimizing your app for Assistive Access](https://developer.apple.com/documentation/accessibility/optimizing-your-app-for-assistive-access) ·
[Apple: `UISupportsAssistiveAccess`](https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportsassistiveaccess) ·
[Apple: `UISupportsFullScreenInAssistiveAccess`](https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportsfullscreeninassistiveaccess) ·
[Apple: `isAssistiveAccessEnabled`](https://developer.apple.com/documentation/accessibility/accessibilitysettings/isassistiveaccessenabled) ·
[Apple: `SceneBuilder.buildLimitedAvailability`](https://developer.apple.com/documentation/swiftui/scenebuilder/buildlimitedavailability(_:)) ·
[Apple: enter and exit Assistive Access](https://support.apple.com/guide/assistive-access-iphone/enter-and-exit-assistive-access-devdedddc678/ios) ·
[Apple: change Assistive Access settings](https://support.apple.com/guide/assistive-access-iphone/dev073880b40/ios)
