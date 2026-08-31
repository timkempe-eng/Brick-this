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

## How it works

```
NFC tag  ──tap──▶  Shortcuts automation  ──▶  ToggleTimIntent
                                                    │
                                              TimEngine.handleTap
                                                    │
                                    ┌───────────────┴───────────────┐
                                    ▼                               ▼
                          ManagedSettingsStore              TimStore (App Group)
                          .shield.applications              active session, modes,
                                    │                       paired tags, history
                                    ▼                               │
                        iOS shields the apps                        ▼
                                    │                     read by the shield
                                    ▼                        extension
                       ShieldConfigurationExtension  ◀──────────────┘
                            "Timmed."
```

The restrictions are held by the system, not by this app. Force-quitting Tim
does not unblock anything. Strict Mode additionally sets `denyAppRemoval`, so
you can't delete Tim to escape it either.

Tim never learns which apps you blocked. `FamilyActivityPicker` hands back
opaque tokens that only iOS can resolve, and those tokens are all that's stored.
Nothing leaves the device — there is no server and no network code.

## Layout

```
Tim/
  Shared/          model + engine, compiled into all four targets
    TimVocabulary  every string carrying the verb, in one place
    TimMode        a Mode and a session
    TimStore       App Group persistence
    Shielder       the ManagedSettings wrapper that does the blocking
    TimEngine      start/stop/toggle — one path for every trigger
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

The core loop is built and the three tap paths are wired up. Stats, widgets,
scheduled Modes and Android are [not done](docs/roadmap.md). None of it has run
on a device yet — it needs your Team ID and the Family Controls capability
before it will compile for one.
