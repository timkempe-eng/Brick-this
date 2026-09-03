# Dad

**Dad your phone. Get the room back.**

Tap an NFC sticker and the apps you chose disappear. Leave the sticker in
another room and they stay gone until someone walks back and taps it again.

> Dad / Dads / Dadding / Dadded. "I Dadded my phone at nine." "Your phone is
> Dadded." "Un-Dad my phone." — [the full verb spec](docs/naming.md)

## The idea

A phone in a house is not one person's willpower problem. It is four devices at
a dinner table, a bedroom light on at midnight, and an argument about the same
thing every evening. The tools built for it mostly point one way — a parent
configures a child's phone, the child works out how to get around it, and the
tool becomes another thing to fight about.

**The household is the unit.** Tags in the kitchen, by the front door, in a
bedroom. Phones belonging to parents and teenagers alike. Everyone plays,
because a rule that runs on exactly one phone in the house is not a habit, it is
a punishment — and a parent's own device habits are among the strongest
predictors of their child's.

The goal is not to police a teenager. It is to make phones less of a constant
presence for everyone under one roof, and to hand a teenager more control over
their own as they show they can hold it.

## What Dad believes

Five commitments. Each one has a consequence in the code, which is the only
reason to write them down.

**1. Everyone is in it, parents included.** Shared streaks and household goals
count every phone in the house. There is no view of the app that exists only for
the adult.

**2. The reward for good decisions is autonomy — never more screen time.** An
entire category pays for chores and homework in minutes: ScreenCoach, Chore
Champ, Carrots&Cake, EarnIt, Zenvy. The research says it backfires — screens
become the thing worth working for, and cooperation turns into "what do I get
for this?". Dad escapes that trap only because of a distinction worth being
precise about: those apps pay for *unrelated* behaviour with the thing they are
trying to limit, whereas here the good decision *is* the habit. So consistency
buys freedom — a later self-set Sleep window, the right to edit your own Modes,
more overrides, eventually the tag living in your own room. Earned minutes are
the one currency Dad will not mint.

**3. Dad is a boundary, not a spy.** Teenagers whose parents used monitoring
apps experienced *more* online risk, not less, and the apps correlate with
eroded trust. Dad cannot monitor anything, and not as a matter of policy:
`FamilyActivityPicker` hands back opaque tokens only iOS can resolve, Core holds
them as a `Data` blob it cannot read, and exactly one adapter file is allowed to
interpret them. The app does not learn which apps were blocked, there is no
server, and no step of a tap touches a network. The privacy model is
structural — see rule 3 in [CLAUDE.md](CLAUDE.md).

**4. The rules get written by both people.** Setup is a negotiation, not a
configuration screen: each Mode proposed and agreed, the reasoning recorded next
to it, and a point in the future where it gets renegotiated. Adolescent
involvement in screen decisions is associated with better compliance and
greater prosociality — it is the best-supported thing in the literature and
close to the cheapest thing to build.

**5. There is an ending.** A teenager who keeps the habit ends up running Dad
the way an adult does, with the tag in their own room and nobody else holding
it. A tool for teaching a habit should plan its own obsolescence.

## What Dad will not do

The declines are as much the design as the features, and each has a reason so it
does not get re-litigated:

- **Read messages or scan content** (Bark, Qustodio). Structurally impossible
  here, and the research says it damages the thing it is meant to protect.
- **Track where a child is.** Surveillance, unreliable by most accounts, and it
  needs an always-on entitlement. A tag on the kitchen table solves the same
  problems with none.
- **Pay for chores or grades in screen time.** See commitment 2.
- **Analyse usage with AI** (Opal). Requires learning what you do, which
  commitment 3 exists to prevent.
- **Alternative unlock gimmicks** — shake, tap a pattern, walk (Unpluq). The tag
  is a better friction because it is somewhere else in the house. A second,
  weaker gate only routes around the first.

## Where this actually is

Being honest about this, because the sections above describe an intention and
the code describes a fact, and they are not the same thing yet.

**Built and tested:** the single-phone loop. Pick a Mode, tap, the apps
disappear, tap, they come back. Three tap paths, Modes with app/category/website
blocking, strict Mode, timed release, scheduled Modes, emergency overrides,
stats and streaks, a Lock Screen widget, and crash reconciliation.

**Designed but not built: everything that makes it a family product.** Two
distinct roles, earned autonomy, co-authored rules, the shared dashboard,
request-and-grant. All of it is ranked, costed and argued in
[PARKING_LOT.md](PARKING_LOT.md). The first item there is a prerequisite rather
than a feature: Dad currently uses Family Controls *individual* authorization,
where the phone's owner is in charge — correct for an adult and useless for a
teenager, who can revoke it in Settings. `requestAuthorization(for: .child)` is
Apple's route to the real thing, and it only works on a device signed into a
child's iCloud account inside an iCloud Family. Nothing else on the list means
much without it.

**Never run on a device.** Screen Time and NFC both no-op in the Simulator, so
the first proof that a tap blocks anything comes from TestFlight.

## Why a sticker and not a $59 puck

[Brick](https://getbrick.com/) proved the mechanism, and the teardown is
unflattering to the price: the puck is a read-only NFC chip with no battery, and
the app is a front end for Apple's Screen Time. A $0.30 NTAG215 sticker does the
identical job, because the product was never the technology — it was putting the
off switch in another room. [The teardown](docs/brick-teardown.md).

That used to be the whole point of this repo. It isn't any more — it is what
makes the household version possible. One puck for one adult is a $59 decision.
Tags in the kitchen, by the door and in two bedrooms, for four phones, is a
$59-per-puck decision nobody makes and a rounding error in stickers. The DIY
part stopped being the objective and became the enabler.

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
bundle ids that carry the entitlement. The widget is the fifth target and
deliberately isn't one of them. Everything else waits on it.

Full walkthrough: **[docs/first-tap.md](docs/first-tap.md)**.

Then buy **NTAG215** stickers, not MIFARE Classic and not anything at 125 kHz —
neither works with an iPhone. Don't stick them to metal.
[Buying guide](docs/nfc-and-tags.md#what-to-buy).

## Tests

The Foundation-only core — session maths, streaks, week boundaries, the verb
forms — builds and tests anywhere, no Mac required:

```bash
swift test                      # 803 tests, seconds, no Mac
./scripts/lint-vocabulary.sh    # the verb never ships lowercased
python3 scripts/preflight.py    # 106 checks on the Xcode wiring
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
[ADR 001](docs/adr/001-ports-and-adapters.md). The family layer arrives the same
way: a role and a grant are new ports, not new framework imports in Core.

The restrictions are held by the system, not by this app. Force-quitting Dad
does not unblock anything. Strict Mode additionally sets `denyAppRemoval`, so
you can't delete Dad to escape it either. If a crash ever leaves the shield and
the stored session disagreeing, `reconcile()` settles it on next launch — in
both directions, so neither a half-finished start nor a half-finished stop can
strand you.

Two roles will eventually need shared state, which Dad has none of today — no
accounts, no network. That is worth spending carefully: it is a real advantage
over Brick, which needs a connection to block or unblock at all. The plan is
in-person and tag-mediated first, CloudKit only if remote grant proves
necessary, and never a backend of our own.

## Working on this

`CLAUDE.md` is the contract — read it before non-trivial work. `PARKING_LOT.md`
is the backlog, and now also where the family design is argued and ranked.
`docs/PROVISIONING.md` records Apple state, which is invisible from inside an
agent session.

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
  Widget/          Lock Screen and Home Screen status — Core plus the store only
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

`swift test` passes — 803 tests covering the whole engine state machine,
recurring schedules, allowances across a day boundary, breaks, the override
allowance, and the session/streak maths. The suite is mutation-checked with
`scripts/mutate.sh`: deliberately breaking the tag guard, the rationing branch,
the allowance's day comparison, the empty-Mode guard, the history bound, the
scheduler floor or the reconcile clear each turns it red.

That claim used to be partly false, which is the argument for the harness. The
override allowance, its 30-day window and the history bound were all written
symbolically in every test, so changing 5 to 500 left the whole suite green
while the app went on saying "of 500". `PromisedNumbersTests` now pins the
numbers the product actually promises.

The app and all four extensions compile cleanly against the iOS SDK on a
GitHub macOS runner, on every push. Nothing has run on a device yet — Screen
Time and NFC both no-op in the Simulator, so the first real proof that a tap
blocks anything comes from TestFlight.
[Day-one checklist](docs/first-tap.md).

What is built, what isn't, and the honest limitations: [docs/roadmap.md](docs/roadmap.md).
