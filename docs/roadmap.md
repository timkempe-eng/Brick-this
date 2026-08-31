# Where this stands

The core loop is complete: pick a Mode, tap, the apps disappear, tap, they come
back. Scheduled Modes, stats and streaks are built on top of it.

The engine, its ports, the schedule maths and the stats are covered by
`swift test` — 98 tests, runnable anywhere. The iOS layer above them (views,
adapters, extensions) has never been compiled; that needs a Mac.

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

## Not built

**A Lock Screen widget and Live Activity.** The status is only visible inside
the app, which is a little absurd for a product about not opening your phone. A
Live Activity showing the running timer is the natural home for it. Worth doing
as a fifth port (`ActivityPresenting`) so the *decision* to start and stop one
stays testable, even though ActivityKit itself won't be. This is the largest
remaining gap.

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

**Nothing above `Tim/Shared/Core` has been compiled.** The views, adapters and
extensions are written but unverified. `scripts/preflight.py` catches the
configuration mistakes that fail silently on device; it cannot catch a type
error. Expect some shakeout on the first Xcode build.

**Stored data has no schema versioning.** Arrays decode leniently, so one bad
record can't destroy a whole history, but a rename like `TimMode.selection` →
`TimMode.blocked` still orphans the old key. Fine before anyone is relying on
it; worth a migration path before it ships to anyone else.

**`DeviceActivitySchedule` pins one weekday per window.** An every-day schedule
collapses to a single repeating window, but a three-day-a-week Mode costs three.
The system caps how many activities an app may monitor, so a large number of
scheduled Modes would eventually hit that ceiling.
