# Tim

**Tim your phone. Get your day back.**

A DIY [Brick](https://getbrick.com/). Tap an NFC sticker and the apps you chose
disappear. Leave the sticker in another room and they stay gone until you walk
back and tap it again.

> Tim / Tims / Timming / Timmed. "I Timmed my phone at nine." "Your phone is
> Timmed." "Un-Tim my phone." — [the full verb spec](docs/naming.md)

Brick charges $59 for a plastic puck. The puck is a read-only NFC chip with no
battery; the app is a front end for Apple's Screen Time. A $0.30 NTAG215 sticker
does the identical job, because the product was never the technology — it was
putting the off switch in another room. [The teardown](docs/brick-teardown.md).

## Quick start

```bash
brew install xcodegen
xcodegen generate
open Tim.xcodeproj
```

Then, before it will build on a device:

1. Set `DEVELOPMENT_TEAM` in `project.yml` to your Apple Developer Team ID and
   run `xcodegen generate` again.
2. In Xcode, add the **Family Controls** capability to all four targets. It's
   available for development straight away; shipping to TestFlight or the App
   Store needs Apple's approval, which takes days to weeks —
   [file it early](docs/entitlements.md).
3. Run on a real iPhone. Screen Time and NFC do not work in the Simulator.
4. Grant Screen Time access when asked, build a Mode, and pair a tag in
   Settings.
5. Set up the Shortcuts automation so a tap works with the app closed —
   [three lines of setup](docs/nfc-and-tags.md#2-shortcuts-automation--the-one-to-use).

Buy **NTAG215** stickers, not MIFARE Classic and not anything at 125 kHz — neither works with an iPhone. Don't stick them to metal. [Buying guide](docs/nfc-and-tags.md#what-to-buy).

## Tests

The Foundation-only core — session maths, streaks, week boundaries, the verb
forms — builds and tests anywhere, no Mac required:

```bash
swift test
```

Everything touching FamilyControls, ManagedSettings, DeviceActivity, CoreNFC or
SwiftUI needs Xcode and a real device, and is deliberately kept out of
`Tim/Shared/Core` so that stays true.

## How it works

```
NFC tag ──tap──▶ Shortcuts automation ──▶ ToggleTimIntent ──┐
                                                            │
  in-app scan ──────────────────────────────────────────────┤
  shield's emergency button ────────────────────────────────┤
  DeviceActivity timed release ─────────────────────────────┤
                                                            ▼
                                                      TimEngine
                                          (Foundation only, fully tested)
                                                            │
              ┌──────────────┬──────────────┬───────────────┘
              ▼              ▼              ▼
      ShieldControlling  SessionScheduling  TimPersisting   ← ports
              │              │              │
      ManagedSettings   DeviceActivity   App Group           ← iOS adapters
              │
      iOS shields the apps ──▶ ShieldConfigurationExtension
                                    "Timmed."
```

Every trigger funnels through one engine, so there is exactly one place a
session can begin or end. The engine depends only on four protocols, which is
what lets the whole state machine be tested without a device —
[ADR 001](docs/adr/001-ports-and-adapters.md).

The restrictions are held by the system, not by this app. Force-quitting Tim
does not unblock anything. Strict Mode additionally sets `denyAppRemoval`, so
you can't delete Tim to escape it either. If a crash ever leaves the shield and
the stored session disagreeing, `reconcile()` settles it on next launch — in
both directions, so neither a half-finished start nor a half-finished stop can
strand you.

Tim never learns which apps you blocked. `FamilyActivityPicker` hands back
opaque tokens that only iOS can resolve, and Core holds them as a `Data` blob
it cannot read — only one adapter file interprets it, to hand the tokens to
ManagedSettings. Nothing leaves the device; there is no server and no network
code.

## Layout

```
Tim/
  Shared/
    Core/          Foundation-only. Built into all four targets, and by
                   Package.swift for `swift test`. No iOS frameworks, ever.
      TimEngine        start/stop/toggle — one path for every trigger
      Ports            the four protocols the engine depends on
      TimMode          a Mode; BlockedSelection is opaque here by design
      TimSession       one stretch of being Timmed
      TimStats         streaks, totals, chart data
      ModeSchedule     recurring windows; wall-clock, not instants
      LenientDecoding  one bad stored record can't cost the whole array
      EmergencyAllowance  five per rolling 30 days
      TimVocabulary    every string carrying the verb, in one place
    Adapters/      the iOS side of each port — thin, no logic worth testing
      ManagedSettingsShield, DeviceActivityScheduler, UserDefaultsStore,
      SystemClock, TimMode+FamilyControls, TimEngine+Live (composition root)
  App/             the SwiftUI app, NFC scanning, App Intents
  Extensions/
    ShieldConfiguration   the "Timmed." screen over blocked apps
    ShieldAction          its two buttons
    ActivityMonitor       ends timed sessions with the app closed
docs/              research, naming, tags, entitlements, roadmap
```

`Tim.xcodeproj` is generated and not committed — rerun `xcodegen generate` after
adding a file.

## Status

The core loop, the three tap paths, and the stats screen are built. Widgets,
scheduled Modes and Android are [not done](docs/roadmap.md).

`swift test` passes — 97 tests covering the whole engine state machine,
recurring schedules, the override allowance, and the session/streak maths. The suite is mutation-checked:
deliberately breaking the tag guard, the allowance, the empty-Mode guard, the
history bound, the scheduler floor or the reconcile clear each turns it red.

The iOS layer — views, adapters, extensions — has never been compiled. It needs
a Mac, your Team ID and the Family Controls capability.
[Day-one checklist](docs/first-tap.md).
