# ADR 006: The second device

**Status:** declined for now, with a trigger
**Date:** 2026-09-03

## Context

The phone is Dadded. The iPad is on the sofa. Ninety seconds later the same
person is on the same apps, and the tag on the kitchen wall has done nothing at
all.

This is not a bug report about Dad; it is the standard failure of every
single-device blocker, Brick included, and it has a hardware cause. **No iPad
has NFC a third-party app can use.** So the mechanism Dad is built on — walk to
the tag, tap it — cannot exist on the second device, and the question is what
the product does about a device it can never be tapped on.

## The constraint

Three first-party facts, in order of how load-bearing they are.

**1. The iPad cannot read the tag.** Apple's iPhone specifications list "NFC
with reader mode" under Cellular and Wireless. The iPad Pro and iPad mini
specifications list Wi-Fi, Bluetooth and Thread — NFC appears nowhere on either
page. Core NFC declares iPadOS 11.0+ availability, which is a *framework*
availability, not a hardware one; the framework's own overview says it "requires
a device that supports Near Field Communication" and tells you to "check the
`readingAvailable` class property before starting a reader session". Apple's
Shortcuts guide carries the same hedge on the NFC automation trigger: "Note: Not
all devices support NFC."

Dad already respects this. `TagScanner.isAvailable` returns
`NFCTagReaderSession.readingAvailable`, and `TagWriter` guards on
`NFCNDEFReaderSession.readingAvailable`. Shipped on an iPad today, the app would
degrade correctly and offer no tap.

*(Older iPads are reported to contain NFC controller silicon for internal
purposes such as accessory pairing. **Unverified**, and irrelevant either way:
what matters is what Core NFC exposes, and Apple ships no iPad whose
specifications claim user-facing NFC.)*

**2. Screen Time itself does sync; Dad's state does not.** Apple's own Screen
Time settings propagate across the devices in a Family Sharing group — Apple
Support says to "update all devices to the latest software version before
turning on or changing your Screen Time settings" so that they "sync across all
the devices in your family group". That is Apple's Screen Time, configured in
Settings by a parent. It is not `ManagedSettingsStore`, whose abstract says only
that it "applies settings to the current user or device" and says nothing about
propagation. **Whether a shield set by a third-party app on one device appears
on another is not documented, and is unverified here.** Nothing in this
repository can test it: it needs two devices and an entitlement that is still
pending.

**3. Dad's own state is device-local by construction.** Everything Dad knows
lives in `group.app.dad.shared`, an App Group — "shared containers and keychain
access groups", used to "communicate using interprocess communication". Inter-
process, on one device. There is no sync, because the project has no accounts,
no server and no network calls, and that is a stated property rather than an
oversight.

## The token problem, which is the real one

Even granting a transport, there is a prior question: is a `BlockedSelection`
meaningful on a second device at all?

Apple's documentation says yes. `ApplicationToken`'s discussion reads:
"`FamilyActivitySelection` provides tokens that devices within the same Family
Sharing group can use to identify applications."

The only public field report says no. A developer testing two devices in one
Family Sharing group encoded a selection on device A, sent it to device B, and
found that "interacting with the token (displaying it, using it in shield)
throws an error saying the token is null" — and, oddly, that the reverse
direction worked. The thread has no Apple reply.

That disagreement is the whole design risk. **If the tokens do not carry, then
every cross-device plan below is dead on arrival**, because the iPad would
receive a selection it cannot resolve and would shield nothing while reporting
success — the exact silent-on-device failure class that `scripts/preflight.py`
exists to catch and cannot catch here. Deciding to build cross-device state
before settling this would be deciding on a coin flip.

## What a second target would cost, specifically

`CLAUDE.md` is explicit that a new target is not just a target. Priced against
this project's actual state:

| Cost | Detail |
|---|---|
| **Four** new bundle ids | An iPad app cannot borrow the iPhone app's extensions: the shield draws itself from `ShieldConfiguration`, its buttons run in `ShieldAction`, and schedules fire in `ActivityMonitor`. One app plus three extensions, on top of the five ids that exist |
| `match` entries | `EXTENSION_IDS` in `fastlane/Fastfile` gains them, and preflight checks that list against the project's targets |
| App IDs in the portal | Registered by hand, capabilities enabled by hand; `match` does not manage capabilities |
| Entitlements files | One per target, per hard rule 6 |
| **Family Controls (Distribution) approval** | The one that matters |

That last row is not a line item, it is the schedule. `docs/PROVISIONING.md`
records the request as submitted 2026-09-02 with **no case id, no
acknowledgement and no status page** — the only way to learn it landed is to
look at the App IDs, and a Routine polls that every three days. Budgeted at a
month. It gates the app reaching a phone *at all*, because the profile that
carries the entitlement (Development) cannot be installed without a Mac and the
one that can be installed over the air (Ad-hoc) comes back without it.

So a second target means starting that clock again, from zero, for a device
nobody has yet proved the first target works on. The first build has not been
installed. Nothing has ever demonstrated that a tap hides an app.

**There is a much cheaper version of "support the iPad", and it should be named
so it is not confused with the expensive one.** `project.yml` sets
`TARGETED_DEVICE_FAMILY: "1"` — iPhone only. Setting it to `"1,2"` makes the
existing targets universal: same bundle ids, same `match` entries, same App IDs,
same pending approval, no new review surface. Family Controls is documented as
iPadOS 15.0+ and `AuthorizationCenter` says "You can authorize parental controls
on any device", so the engine, the Modes, the schedules and the shield would all
work. The iPad would simply have no tap, and would have to be Dadded from inside
the app — which is the behaviour ADR 002 declined a Live Activity over. That is
a real trade, not a free win, but it costs one build setting rather than a month
of Apple's time.

## Alternatives considered

**Tap the phone, both devices obey.** The right product answer and the most
expensive one. It needs the iPad to learn about a session it did not start,
which means state crossing devices, which means one of:

- *CloudKit.* Apple's server, not ours — but it is still an iCloud container,
  an entitlement Dad does not have (hard rule 7), a network call in an app whose
  Family Controls justification says "there is no server, no account, no network
  call and no analytics", and a dependency on the user being signed into iCloud.
  Changing that description while the approval it was filed under is still
  pending is a bad trade at a bad moment.
- *`NSUbiquitousKeyValueStore`.* Lighter — 1 MB, 1,024 keys, and it "propagates
  that data to devices with the same Apple account", which is closer to the
  shape of the problem than CloudKit is. Still an iCloud entitlement, still
  requires App Store distribution, and Apple warns against storing personal or
  sensitive data in it because "the system stores the information on disk in an
  unencrypted format". A `BlockedSelection` is opaque, not personal, so that
  warning may not bite — but "may not" is not a foundation.

Both are blocked behind the token question above, which neither of them
answers.

**Child authorization.** `FamilyControlsMember.child` exists — "a parent or
guardian must enter their authorization credentials" — and Family Controls
"requires Family Sharing for user enrollment" regardless. This is the API shape
for the parent-installs-on-child's-device story, and it would let a household
adult authorize Dad on the young person's iPad. It solves *authorization*. It
does not solve *the tap*, which is what the iPad lacks, and it changes what Dad
is: `docs/PROVISIONING.md` tells Apple, in the justification already filed, that
Dad is "a single-user focus tool… There is no second account, no parent or child
role, no remote administration". Introducing `.child` makes that sentence false.

**A physical answer.** Keep the iPad where the tag is. Costs nothing, ships
today, works, and is not a software feature — but it is the honest answer for a
household of one or two people, which is the only household this has.

**Decline outright, permanently.** Rejected: the iPad is a real hole, and iPad
NFC is the only part of this that is genuinely settled forever.

## Decision

**Declined for now.** Dad stays an iPhone app. No sixth bundle id, no iCloud
entitlement, no cross-device state, and no `.child` authorization.

The reason is sequencing rather than principle. Three things are unknown, and
two of them are unknowable from here: whether a tap blocks an app at all,
whether `ApplicationToken`s resolve on a second device, and whether
`ManagedSettingsStore` propagates. Committing a month of Apple review time and
four new bundle ids to a design that rests on all three would be building on
guesses — and this project has already paid for the habit of guessing at Apple's
behaviour once, in `docs/PROVISIONING.md`'s account of the Family Controls
request form.

### Trigger for revisiting

Reopen when **both** hold:

1. **Family Controls (Distribution) is approved and a build is on the phone**,
   with a tap proven to hide an app. Until that is true there is no first
   device, let alone a second.
2. **The token question is answered on real hardware.** Encode a
   `BlockedSelection` on the iPhone, decode it on an iPad in the same Family
   Sharing group, and shield with it. Apple's `ApplicationToken` documentation
   and the only public field report disagree; one experiment settles it and it
   costs an afternoon once (1) is true.

If (2) comes back negative, close this permanently — cross-device Dad is not
constructible, and the answer is the physical one.

If (2) comes back positive, the first step is `TARGETED_DEVICE_FAMILY: "1,2"`
and nothing else: ship the universal app, let the iPad be Dadded from inside the
app, and see whether the missing tap actually matters before spending a bundle
id on it.

## Consequences

- The iPad hole stays open, and `docs/roadmap.md`'s "honest limitations" is
  where it should be written down.
- `PARKING_LOT.md` gains the two-device token experiment as a step in the
  first-build runbook — it is a fifteen-minute test to run while the phone is
  already in hand, and it is worth far more than it costs.
- The Family Controls justification filed with Apple stays accurate: single
  user, no parent or child role, no network. That sentence is now protected by
  two ADRs.
- The app's existing `readingAvailable` guards mean that if the universal build
  is ever made, the iPad degrades to "no tap here" rather than crashing or
  lying. Nothing needs writing to make that true; it already is.

## Sources

- iPhone specifications list "NFC with reader mode":
  <https://www.apple.com/iphone-17-pro/specs/>
- iPad specifications list no NFC of any kind:
  <https://www.apple.com/ipad-pro/specs/> and
  <https://www.apple.com/ipad-mini/specs/>
- Core NFC — "requires a device that supports Near Field Communication… check
  the `readingAvailable` class property before starting a reader session":
  <https://developer.apple.com/documentation/corenfc>
- Shortcuts NFC trigger — "Note: Not all devices support NFC.":
  <https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios>
- Family Controls — iPadOS 15.0+; "You can authorize parental controls on any
  device": <https://developer.apple.com/documentation/familycontrols> and
  <https://developer.apple.com/documentation/familycontrols/authorizationcenter>
- `FamilyControlsMember.child` — "a parent or guardian must enter their
  authorization credentials":
  <https://developer.apple.com/documentation/familycontrols/familycontrolsmember>
- "Use of Family Controls requires Family Sharing for user enrollment":
  <https://developer.apple.com/help/glossary/family-controls>
- `ManagedSettingsStore` — "applies settings to the current user or device"; no
  documented cross-device behaviour:
  <https://developer.apple.com/documentation/managedsettings/managedsettingsstore>
- `ApplicationToken` — "`FamilyActivitySelection` provides tokens that devices
  within the same Family Sharing group can use to identify applications":
  <https://developer.apple.com/documentation/managedsettings/applicationtoken>
- Contradicting field report, no Apple reply — a selection sent between two
  devices in one Family Sharing group yields a token that is null in use:
  <https://developer.apple.com/forums/thread/769955>
- Apple's Screen Time settings sync across a family group's devices (Apple's
  own Screen Time, not third-party `ManagedSettings`):
  <https://support.apple.com/en-us/108806>
- App Groups — "shared containers and keychain access groups, and communicate
  using interprocess communication (IPC)":
  <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups>
- `NSUbiquitousKeyValueStore` — "propagates that data to devices with the same
  Apple account"; 1 MB and 1,024 keys; requires the iCloud key-value store
  entitlement and App Store distribution; "Don't store personal or sensitive
  information in the key-value store":
  <https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore>
- CloudKit — iCloud containers, capability and container configuration
  required: <https://developer.apple.com/documentation/cloudkit>
- In-repo: `docs/PROVISIONING.md` (approval submitted 2026-09-02, no case id,
  Development-vs-Ad-hoc profile table), `fastlane/Fastfile` (`EXTENSION_IDS`),
  `project.yml` (`TARGETED_DEVICE_FAMILY: "1"`), `Dad/App/TagScanner.swift` and
  `Dad/App/TagWriter.swift` (`readingAvailable` guards).
