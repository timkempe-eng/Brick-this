# Dad

**Dad your phone. Get your day back.**

A DIY [Brick](https://getbrick.com/). Tap an NFC sticker and the apps you chose
disappear. Leave the sticker in another room and they stay gone until you walk
back and tap it again.

> Dad / Dads / Dadding / Dadded. "I Dadded my phone at nine." "Your phone is
> Dadded." "Un-Dad my phone." — [the full verb spec](docs/naming.md)

Brick charges $59 for a plastic puck. The puck is a read-only NFC chip with no
battery; the app is a front end for Apple's Screen Time. A $0.30 NTAG215 sticker
does the identical job, because the product was never the technology — it was
putting the off switch in another room. [The teardown](docs/brick-teardown.md).

## Quick start

There is no Mac in this project. GitHub's macOS runners have Xcode on them and
are free for public repositories, so the Mac is a rented one that exists for
four minutes per push.

- **Every push** compiles the app and all four extensions against the real iOS
  SDK, and runs the tests and checks. Green means it builds.
- **To get it on your phone**, run the *Release to TestFlight* workflow from the
  Actions tab — which works from an iPad — then install from TestFlight.

The one unavoidable cost is the **Apple Developer Program, $99/year**. Free
provisioning needs Xcode on a Mac, sideloading tools can't grant the Family
Controls entitlement, and Swift Playgrounds on iPad can't build app extensions
(Dad has four). TestFlight is the only Mac-free route onto a phone, and it
requires the paid program.

Signing is fastlane `match`, not Xcode automatic signing —
[why that distinction costs a week](docs/signing.md).

Start the **Family Controls (Distribution)** entitlement request the day you
enrol: it's a manual review at Apple, days to weeks, needed for each of the four
bundle ids. Everything else waits on it.

Full walkthrough: **[docs/first-tap.md](docs/first-tap.md)**.

Then buy **NTAG215** stickers, not MIFARE Classic and not anything at 125 kHz —
neither works with an iPhone. Don't stick them to metal.
[Buying guide](docs/nfc-and-tags.md#what-to-buy).

## Tests

The Foundation-only core — session maths, streaks, week boundaries, the verb
forms — builds and tests anywhere, no Mac required:

```bash
swift test                      # 240 tests, seconds, no Mac
./scripts/lint-vocabulary.sh    # the verb never ships lowercased
python3 scripts/preflight.py    # 94 checks on the Xcode wiring
```

CI runs all three on Linux, plus a fourth job on a macOS runner that actually
compiles the app and extensions.

`preflight.py` checks the Xcode wiring that fails *silently* on a device — a
mismatched App Group leaves the shield showing the wrong Mode while the app
works fine; a principal-class typo makes an extension never launch. All of it
is checkable without a Mac, so it is.

Everything touching FamilyControls, ManagedSettings, DeviceActivity, CoreNFC or
SwiftUI needs Xcode and a real device, and is deliberately kept out of
`Dad/Shared/Core` so that stays true.

## How it works

```
NFC tag ──tap──▶ Shortcuts automation ──▶ ToggleDadIntent ──┐
                                                            │
  in-app scan ──────────────────────────────────────────────┤
  shield's emergency button ────────────────────────────────┤
  DeviceActivity timed release ─────────────────────────────┤
                                                            ▼
                                                      DadEngine
                                          (Foundation only, fully tested)
                                                            │
      ┌───────┬───────┴───────┬───────────────┬───────────┐
      ▼       ▼               ▼               ▼           ▼
 Shield-  Session-        UsageWatching  DadPersisting  Widget-      ← ports
 Controlling Scheduling                                 Refreshing
      │       │               │               │           │
 Managed-  Device-        DeviceActivity   App Group    WidgetKit    ← adapters
 Settings  Activity       (usage events)
              │
      iOS shields the apps ──▶ ShieldConfigurationExtension
                                    "Dadded."
```

Every trigger funnels through one engine, so there is exactly one place a
session can begin or end. The engine depends only on six protocols (`Clock` is
the sixth, and the reason time-dependent behaviour is testable at all), which
is what lets the whole state machine be tested without a device —
[ADR 001](docs/adr/001-ports-and-adapters.md).

The restrictions are held by the system, not by this app. Force-quitting Dad
does not unblock anything. Strict Mode additionally sets `denyAppRemoval`, so
you can't delete Dad to escape it either. If a crash ever leaves the shield and
the stored session disagreeing, `reconcile()` settles it on next launch — in
both directions, so neither a half-finished start nor a half-finished stop can
strand you.

Dad never learns which apps you blocked. `FamilyActivityPicker` hands back
opaque tokens that only iOS can resolve, and Core holds them as a `Data` blob
it cannot read — only one adapter file interprets it, to hand the tokens to
ManagedSettings. Nothing leaves the device; there is no server and no network
code.

## Working on this

`CLAUDE.md` is the contract — read it before non-trivial work. `PARKING_LOT.md`
is the backlog. `docs/PROVISIONING.md` records Apple state, which is invisible
from inside an agent session.

## Layout

```
Dad/
  Shared/
    Core/          Foundation-only. Built into all five targets, and by
                   Package.swift for `swift test`. No iOS frameworks, ever.
      DadEngine        start/stop/toggle — one path for every trigger
      Ports            the six protocols the engine depends on
      DadMode          a Mode; BlockedSelection is opaque here by design
      DadSession       one stretch of being Dadded
      DadStats         streaks, totals, chart data
      ShieldPolicy     whether the apps are currently taken away — one answer
      ModeSchedule     recurring windows; wall-clock, not instants
      ModeAllowance    a daily budget, for a Mode that rations rather than hides
      PendingResume    a break: released by hand, coming back on its own
      WidgetSnapshot   what the Lock Screen says, decided here not in the widget
      SchemaCoding     stored values carry the version that wrote them
      LenientDecoding  one bad stored record can't cost the whole array
      EmergencyAllowance  five per rolling 30 days
      DadVocabulary    every string carrying the verb, in one place
    Adapters/      the iOS side of each port — thin, no logic worth testing
      ManagedSettingsShield, DeviceActivityScheduler, DeviceActivityUsageWatcher,
      UserDefaultsStore, WidgetKitRefresher, SystemClock,
      DadMode+FamilyControls, DadEngine+Live (composition root)
  App/             the SwiftUI app, NFC scanning, App Intents
  Extensions/
    ShieldConfiguration   the "Dadded." screen over blocked apps
    ShieldAction          its two buttons
    ActivityMonitor       ends timed sessions, and rations, with the app closed
  Widget/          the Lock Screen widget — Core plus one adapter, no
                   Screen Time entitlement, deliberately
hardware/          the printable puck; rendered by CI, not committed
docs/              research, naming, tags, entitlements, roadmap, ADRs
```

`Dad.xcodeproj` is generated and not committed — rerun `xcodegen generate` after
adding a file.

## Status

The core loop, the three tap paths, scheduled Modes, the Lock Screen widget,
the stats screen, allowance Modes, breaks and the never-blocked list are built.
A Live Activity and Android are both **declined with reasons written down**
rather than pending — [ADR 002](docs/adr/002-no-live-activity.md) and
[ADR 004](docs/adr/004-android.md). [What is and isn't built](docs/roadmap.md).

`swift test` passes — 240 tests covering the whole engine state machine,
recurring schedules, allowances across a day boundary, breaks, the override
allowance, and the session/streak maths. The suite is mutation-checked with
`scripts/mutate.sh`: deliberately breaking the tag guard, the rationing branch,
the allowance's day comparison, the empty-Mode guard, the history bound, the
scheduler floor or the reconcile clear each turns it red.

The app and all four extensions compile cleanly against the iOS SDK on a
GitHub macOS runner, on every push. Nothing has run on a device yet — Screen
Time and NFC both no-op in the Simulator, so the first real proof that a tap
blocks anything comes from TestFlight.
[Day-one checklist](docs/first-tap.md).
