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
- [x] ~~**Live Activity.**~~ Investigated and declined — ActivityKit can only
      start one from the foreground, which is the one path Tim exists to
      avoid. It would appear only when you Timmed by opening the app.
      [ADR 002](docs/adr/002-no-live-activity.md).

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

## Closed (this sweep)

- [x] **The schedule toggle was never broken.** Four CI runs chased a
      "schedule can't be turned on" bug that did not exist. The UI test
      asserted the footer would promise "your phone Tims itself"; the app
      refused, because a starter Mode blocks nothing and a Mode that blocks
      nothing is never registered with the scheduler — so it says what is
      still missing instead. The app was right every time. Two lessons, both
      paid for: assert the behaviour the product actually specifies, not the
      one you assumed; and read *which* assertion failed before theorising —
      the first one had been passing since run 27, which alone ruled out the
      binding.

- [x] **Schema versioning.** Stored values now carry the version that wrote
      them, so a future shape change migrates instead of silently resetting
      Modes and history. Data written by a *later* build is detected and
      reported rather than treated as corrupt, so a TestFlight rollback can't
      destroy what it merely fails to understand. Done now because it costs
      nothing before the first install and can't be retrofitted cleanly after.
- [x] **Simulator launch test.** The app provably launches, renders and
      survives a relaunch — which compilation never showed.
- [x] Mutation harness (`scripts/mutate.sh`). The hand-rolled loop decided by
      grepping for "with N failures" and XCTest prints "with 1 failure", so
      every mutation caught by exactly one test read as a survivor. Blamed on
      stale builds three times before the regex turned out to be the cause.

- [x] **Lock Screen widget.** Status and a live timer without unlocking. What
      it says lives in Core as `WidgetSnapshot` and is tested; the extension is
      layout. A fifth port, `WidgetRefreshing`, means every process that can
      end a session — the app, the shield's emergency button, the
      DeviceActivity monitor — clears the Lock Screen.
- [x] An unrecognised deep link no longer toggles. `tim://open` would have
      fallen through to the toggle default, so tapping the widget to *check*
      your status would have released a live session.

- [x] Full-codebase review: ten findings, nine fixed, one wired into the UI.
      The scheduler adapter was the cluster — cross-midnight weekday windows
      ended a week late, any edit tore down every window including open ones,
      and registration failures were recorded as success. Window arithmetic
      and the change-diff now live in Core and are tested; the adapter only
      maps them onto DeviceActivity.
- [x] A schedule boundary can no longer end a session you started by hand
      with the same Mode — sessions carry a started-by-schedule marker.
- [x] A timed session now ends (or re-arms) at reconcile even if its release
      registration was lost with the process.

## Closed

- [x] Engine testable at all — ports and adapters, 98 tests (was 15)
- [x] iOS layer compiles, on a GitHub macOS runner, every push
- [x] Scheduled Modes
- [x] Stats and streaks
- [x] Signing reworked to `match` after reading the hydive playbook
