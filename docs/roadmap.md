# Where this stands

The core loop is complete: pick a Mode, tap, the apps disappear, tap, they come
back. Scheduled Modes, stats and streaks are built on top of it.

The engine, its ports, the schedule maths and the stats are covered by
`swift test` — 98 tests, runnable anywhere. The iOS layer above them compiles
on every push, on a GitHub macOS runner. Neither needs a Mac of your own.

## Built

- **The tap**, three ways: in-app Core NFC scan, an App Intent for the Shortcuts
  NFC automation, and universal links for background tag reading.
- **Modes** — app, category and website blocking, strict mode, timed release.
- **Scheduled Modes** — recurring wall-clock windows that never override a
  session you started by hand.
- **Emergency overrides** — five per rolling 30 days, self-restoring.
- **Stats and streaks** — `TimStats` plus `StatsView`.
- **Crash reconciliation** — the shield and the stored session are made to agree
  on every foreground, in both directions.
- **Lock Screen widget** — status and a live timer without unlocking, in all
  three accessory families plus a Home Screen tile.

## Not built

**A Live Activity — declined, not pending.** ActivityKit only starts one from
the foreground, so it could never appear on the tap-and-pocket path the product
is built around. [ADR 002](adr/002-no-live-activity.md) has the reasoning.

**Allowance rather than blocking.** Screen Time can throttle instead of forbid.
A Mode granting fifteen minutes of an app per day is a softer tool than a hard
shield, and sometimes the right one.

**Android.** A different mechanism entirely — an `AccessibilityService` watching
the foreground package rather than a system-enforced shield. `Tim/Shared/Core`
is Foundation-only and would port more or less directly; the adapters would all
be new, and blocking would be meaningfully weaker.

**A nicer tag.** A 3D-printed puck with a magnet and some ballast. Purely
cosmetic, entirely worth it.

## Known limitations

**Compiled and launched, but never used in anger.** The app now provably comes
up and renders on a Simulator in CI. Screen Time and NFC still no-op there, so
the first evidence that a tap actually blocks an app remains TestFlight.

**Nothing in the Simulator can block anything, so nothing there can be fully
configured either.** `FamilyActivityPicker` returns no apps, which means every
Mode a UI test can reach blocks nothing, which means no schedule it turns on
will ever be registered. The app says so — a scheduled Mode that blocks nothing
tells you what is still missing instead of promising to Tim your phone — and
that honesty is the deepest a Simulator test can go. Configuring a Mode
end-to-end is a TestFlight step.

**`DeviceActivitySchedule` pins one weekday per window.** An every-day schedule
collapses to a single repeating window, but a three-day-a-week Mode costs three.
The system caps how many activities an app may monitor; hitting the ceiling is
now reported — the sync refuses to record itself and the editor says so —
rather than a schedule that looks configured and silently never fires.
