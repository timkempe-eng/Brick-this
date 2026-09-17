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

## Guided Access, which is not this and is worth knowing about

The two names are close enough that the first attempt at the triple-click on a
real phone landed on the wrong one: the Accessibility Shortcut was bound to
Guided Access, and produced *"Guided Access is unavailable. Open an app to start
Guided Access."* on the Home Screen.

They are different features. **Guided Access locks the phone into the one app
that is already open** — hence needing an app first. **Assistive Access
simplifies the whole phone.** Only the second is what this product wants.

The interesting part is the API. `UIAccessibility` has shipped
`requestGuidedAccessSession(enabled:completionHandler:)` since **iOS 7**: an app
*can* put a device into Single App mode programmatically. Apple's own words on
the requirement: "Entering Single App mode is supported only for devices that
are supervised using Mobile Device Management (MDM), and the app itself must be
enabled for this mode by MDM."

So the capability exists, is a decade old, and is gated behind enterprise
supervision rather than absent. That is a materially different fact from "Apple
has never built this", and it is the strongest available argument when asking
for the consented, user-owned version: the ask is to widen an existing
mechanism, not to invent one. It does not change what this app can do today —
Dad is a consumer app on unsupervised phones, so the gate is closed — and a
supervised phone is only free to set up on the day somebody wipes it, which is
the same wall [ADR 004](004-android.md) hit on the other platform.

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

## Amendment, 2026-09-17: pair the tap with the triple-click

The first version of this decision stopped at "Dad runs inside it". That leaves
the thing people actually want — a phone that visibly becomes simpler when you
tap the tag — entirely to the user's memory. Dad cannot perform the second half
of the gesture, but it can ask for it at the only moment the person is
certainly holding the phone: the second after they tapped.

So a Mode may ask. `DadMode.wantsAssistiveAccess` is off by default and per
Mode, because taking the whole interface down to a few buttons is right for
Sleep and absurd for Gym. When such a Mode starts, the engine posts one notice
through the `Notifying` port: *"Sleep is on. Triple-click the side button (or
Home) for Assistive Access."*

Three things this deliberately does not do:

- **It does not claim to switch anything.** The prompt is an instruction to a
  person, and the copy says so.
- **It does not share the warning's slot.** `Notifying` gained `post` beside
  `setPendingWarning` rather than reusing it, because that slot is
  single-occupancy and self-clearing by design — a tap would otherwise have
  silently cancelled tonight's ten minutes' notice.
- **It does not prompt from the DeviceActivity extension.** That process holds
  a `SilentNotifier` and cannot ask for notification permission, so a
  *scheduled* Mode that asks for Assistive Access starts without saying so.
  Recorded as a limitation in `docs/roadmap.md` rather than papered over.

**The way out is the asymmetry that matters.** Leaving Assistive Access needs
its passcode, which Dad neither knows nor can ask for; and whether a Shortcuts
NFC automation even fires inside the mode is unknown from here. So the release
is the same two steps in reverse — triple-click out, then tap — and that order
is spelled out in three places: the Assistive Access screen itself, the Settings
setup notes, and the warning beside them that whoever will need the passcode
must have it. A friction that can strand somebody is not a friction, and the
tag being in another room is exactly the case this feature makes worse if the
order is left to be guessed.

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
