# Where this stands

The core loop is complete: pick a Mode, tap, the apps disappear, tap, they come
back. Scheduled Modes, stats and streaks are built on top of it.

The engine, its ports, the schedule maths and the stats are covered by
`swift test` — 834 tests, runnable anywhere. The iOS layer above them compiles
on every push, on a GitHub macOS runner. Neither needs a Mac of your own.

## Built

- **The tap**, three ways: in-app Core NFC scan, an App Intent for the Shortcuts
  NFC automation, and universal links for background tag reading.
- **Modes** — app, category and website blocking, strict mode, timed release.
- **Scheduled Modes** — recurring wall-clock windows that never override a
  session you started by hand.
- **Emergency overrides** — five per rolling 30 days, self-restoring.
- **Stats and streaks** — `DadStats` plus `StatsView`.
- **Crash reconciliation** — the shield and the stored session are made to agree
  on every foreground, in both directions.
- **Lock Screen widget** — status and a live timer without unlocking, in all
  three accessory families plus a Home Screen tile.
- **Allowance Modes** — a Mode can ration rather than forbid: the apps stay
  usable for a set number of minutes a day, then go until midnight. Strict
  still holds through the free period, and an allowance the system refuses to
  count becomes a plain block rather than a rule nobody is enforcing.
- **Breaks — release on a leash.** Opt-in per Mode: tapping out gives the apps
  back for a set time, then the Mode starts itself again, so checking one thing
  doesn't cost the evening. Tapping a second time calls the break off. An
  emergency override never starts one.
- **The family layer.** Two roles with permissions derived rather
  than stored; an **autonomy ladder** where consistency buys control and never
  minutes, with every rung visible from day one; **request and grant**, where a
  young person asks and a grown-up answers by tapping their own tag, bounded by
  construction so saying yes is not giving up for the evening; **skip tonight**
  for one occurrence of a schedule; a **weekly review** aimed at a conversation
  rather than a report card; and **co-authored agreements** recording why a Mode
  exists and when it gets renegotiated.
- **Allowlist Modes** — a Mode can name what stays rather than what goes, which
  is the only shape here that improves with time instead of decaying.
- **A tag per Mode** — the kitchen tag starts Dinner, the desk tag starts Deep
  Work. The first migration the schema ladder has actually run.
- **A never-blocked list** — apps and sites no Mode may take away, whatever it
  names. One list, not one per Mode, because the failure it exists to prevent
  is forgetting.
- **A shared streak on the tag itself** — the days *everyone* in the house took
  part, so the grown-up's phone can end it. The tag is the courier: a tap made
  inside the app reads the ledger off it, merges, and writes it back, so the
  feature costs no account, no server and no network. It carries an opaque id,
  a date and a count and could not carry a name if somebody tried, and it says
  which day the number is true as of rather than pretending to be live.
- **Rewards priced in days** — earned by ending sessions yourself, spent
  on things a grown-up offers. Never in minutes, and not by convention:
  `RewardLedger.Days` has no multiply, no `Double` and no duration member, so
  paying in screen time does not compile. Offering and settling need a grown-up
  demonstrably in the room; claiming does not, because the balance is the
  permission and it was earned.
- **Ten minutes' notice** before a scheduled Mode lands, over the `Notifying`
  port. It names the Mode and the time, asks for nothing, and makes no sound.
- **Saying when the shield went missing** — as an upper bound, never a
  measurement, with the caveat beside the number rather than in a help screen.
  An adult Dadding their own phone is told nothing about the past.
- **A puck to put the tag in** — [hardware/](../hardware/), two printed parts,
  about a dollar, rendered by CI rather than committed.

## Not built

**A Live Activity — declined, not pending.** ActivityKit only starts one from
the foreground, so it could never appear on the tap-and-pocket path the product
is built around. [ADR 002](adr/002-no-live-activity.md) has the reasoning.

**Family Controls child authorization.** The one piece of the family layer
still missing, and the one that makes the rest binding rather than
co-operative: Dad authorizes as an *individual*, so the phone's owner is in
charge and a young person can revoke it in Settings. `.child` authorization is
Apple's blessed route and needs the device signed into a child iCloud account
inside an iCloud Family. Everything above works today as an agreement between
two people who both want it to; this is what makes it hold when one of them
doesn't.

**Remote granting.** `GrantRequest` defines a `PINHashing` port and nothing
implements it: the first shape of granting is in-person, because the parent
already holds a tag and a tag needs no account, server or crypto. A PIN is what
that becomes when they are not in the room.

**A digest of what you missed while Dadded — declined.** Reviewers of every
blocker ask for it, and iOS does not expose enough to build it honestly. A
half-true digest is worse than none: it teaches people to check it, and then to
distrust it. [ADR 005](adr/005-missed-while-dadded.md).

**The second device — declined for now, with a price on it.** The iPad has no
NFC, so the tag cannot reach it, and covering it costs a new bundle id, a
`match` entry, another Family Controls approval and cross-device state.
[ADR 006](adr/006-the-second-device.md) names what would make it worth paying.

**Android — declined in the form everyone builds it in.** The only consumer
mechanism is an `AccessibilityService` the user turns off in three taps, which
is the exact failure the whole product exists to avoid; and Android 17's
Advanced Protection Mode is closing that API to non-accessibility apps
regardless. The version that *would* work — `setPackagesSuspended` under
device-owner — is stronger than the iOS shield and needs the phone provisioned
from a factory reset, which is only free on the day someone sets a phone up for
somebody else. [ADR 004](adr/004-android.md) has the reasoning and the trigger
to revisit.

## Known limitations

**Compiled and launched, but never used in anger.** The app now provably comes
up and renders on a Simulator in CI. Screen Time and NFC still no-op there, so
the first evidence that a tap actually blocks an app remains TestFlight.

**Nothing in the Simulator can block anything, so nothing there can be fully
configured either.** `FamilyActivityPicker` returns no apps, which means every
Mode a UI test can reach blocks nothing, which means no schedule it turns on
will ever be registered. The app says so — a scheduled Mode that blocks nothing
tells you what is still missing instead of promising to Dad your phone — and
that honesty is the deepest a Simulator test can go. Configuring a Mode
end-to-end is a TestFlight step.

**The shared streak is always one tap behind on the phone that writes it.**
The ledger has to be computed before the NFC session opens — the merge runs on
a background queue where nothing may touch the store — and the tap that ends
tonight's session is processed after the session closes. So the standing this
phone leaves on the tag is the one it had *before* the tap, and tonight only
reaches the tag on the next one.

It lags rather than lies: `HouseholdStreak.asOf` carries the day the number is
true as of, and the copy says it. Fixing it properly needs a second NFC session
after the tap — a second "hold your iPhone near the tag" prompt for something
nobody asked for — which is a worse trade than a number that is honest about
being a tap old.

**An allowance has never been counted on a device.** The rationing state
machine is covered by `swift test` end to end — including the day boundary, the
refusal path and the re-arm — but every one of those tests drives it through a
fake. Whether iOS actually delivers `eventDidReachThreshold` for a threshold
registered mid-day, and how promptly, is the one thing only TestFlight can say.
The engine is built so that being wrong about it fails safe: an allowance the
system will not count becomes a block, and a midnight wake that never arrives is
corrected on the next foreground.

**Partial allowance use is not carried between sessions.** Once a rationed
Mode's daily limit is *reached* it stays reached for the rest of the day, across
as many sessions as you start — otherwise ending and re-tapping would be a
two-tap reset. But the system only reports the moment a threshold is crossed
and nothing before it, so ten minutes used in a session you ended early are ten
minutes Dad never hears about, and the next session starts with the full
allowance. A smaller hole than the one it replaces, and not closable with the
API as it stands.

**A protected app inside a blocked *category* still spends a rationed Mode's
allowance.** ManagedSettings expresses "this category except these apps"
natively, so the never-blocked list works properly for the shield. A
`DeviceActivityEvent` has no equivalent `except:`, so a Mode that rations the
Social category counts every app in it — including one you protected. The app
stays reachable, which is the part that matters; it just costs you minutes it
shouldn't. Naming apps rather than categories in a rationed Mode avoids it
entirely.

**`DeviceActivitySchedule` pins one weekday per window.** An every-day schedule
collapses to a single repeating window, but a three-day-a-week Mode costs three.
The system caps how many activities an app may monitor; hitting the ceiling is
now reported — the sync refuses to record itself and the editor says so —
rather than a schedule that looks configured and silently never fires.
