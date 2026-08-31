# Parking lot

Swept after every merge: check off what closed, **correct what is now wrong**,
add what the work revealed.

## Blocked on Apple (calendar time, not work)

- [ ] Apple Developer Program enrolment
- [ ] Family Controls (Distribution) approved for all four bundle ids
- [ ] Capability enabled on each App ID — a separate step from approval, and
      `match` does not do it. After enabling, run Release once with
      `force_profiles: true` or match reuses a profile that predates it.
- [ ] App Store Connect API key → the three `ASC_*` secrets, `APPLE_TEAM_ID`,
      `MATCH_PASSWORD`
- [ ] App Store Connect record for `app.tim.Tim`
- [ ] First TestFlight build installed on the iPhone

## Next up

- [ ] **Rename the default branch to `main`.** `main` is pushed; flip it in
      Settings → Branches and delete the session branch.
- [ ] **Run Apple account maintenance before the first Release run.** Tim mints
      its own distribution certificate, and Apple's ceiling is about two. Know
      the count before it matters.
- [ ] **Lock Screen widget / Live Activity.** The largest remaining product
      gap — the status is only visible inside the app, which is absurd for a
      product about not opening your phone. Do it as a fifth port
      (`ActivityPresenting`) so the decision to start and stop one stays
      testable even though ActivityKit isn't.

## Later

- [ ] Allowance-based Modes — Screen Time can throttle rather than forbid.
- [ ] Android. `Tim/Shared/Core` would port nearly as-is; every adapter is new,
      and blocking via `AccessibilityService` is meaningfully weaker.
- [ ] 3D-printed puck with a magnet, instead of a bare sticker.

## Known limitations, carried deliberately

- **Compiled, never run.** Screen Time and NFC both no-op in the Simulator, so
  nothing before TestFlight proves a tap blocks anything.
- **No schema versioning.** Arrays decode leniently so one bad record can't
  destroy a history, but a key rename still orphans the old value. Fine before
  anyone relies on it; needs a migration path before it ships to anyone else.
- **`DeviceActivitySchedule` pins one weekday per window.** An every-day
  schedule collapses to one window; a part-week Mode costs several against the
  system's activity cap.

## Closed

- [x] Engine testable at all — ports and adapters, 98 tests (was 15)
- [x] iOS layer compiles, on a GitHub macOS runner, every push
- [x] Scheduled Modes
- [x] Stats and streaks
- [x] Signing reworked to `match` after reading the hydive playbook
