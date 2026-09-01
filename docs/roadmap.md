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

**A Live Activity.** The Lock Screen widget below covers the glance; a Live
Activity would add the Dynamic Island and a richer running presentation while a
session is open. The `WidgetRefreshing` port generalises to it.

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

**Compiled, but never run.** The app and all three extensions build cleanly
against the iOS SDK in CI, so the code is type-checked and links. Nothing has
executed on a device: Screen Time and NFC both no-op in the Simulator, so the
first real evidence that a tap blocks anything comes from TestFlight.

**Stored data has no schema versioning.** Arrays decode leniently, so one bad
record can't destroy a whole history, but a rename like `TimMode.selection` →
`TimMode.blocked` still orphans the old key. Fine before anyone is relying on
it; worth a migration path before it ships to anyone else.

**`DeviceActivitySchedule` pins one weekday per window.** An every-day schedule
collapses to a single repeating window, but a three-day-a-week Mode costs three.
The system caps how many activities an app may monitor; hitting the ceiling is
now reported — the sync refuses to record itself and the editor says so —
rather than a schedule that looks configured and silently never fires.
