# Where this stands

The core loop is complete: pick a Mode, tap, the apps disappear, tap, they come
back. Scheduled Modes, stats and streaks are built on top of it.

The engine, its ports, the schedule maths and the stats are covered by
`swift test` — 240 tests, runnable anywhere. The iOS layer above them compiles
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
- **A never-blocked list** — apps and sites no Mode may take away, whatever it
  names. One list, not one per Mode, because the failure it exists to prevent
  is forgetting.
- **A puck to put the tag in** — [hardware/](../hardware/), two printed parts,
  about a dollar, rendered by CI rather than committed.

## Not built

**A Live Activity — declined, not pending.** ActivityKit only starts one from
the foreground, so it could never appear on the tap-and-pocket path the product
is built around. [ADR 002](adr/002-no-live-activity.md) has the reasoning.

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
