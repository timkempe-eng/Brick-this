# Parking lot

Swept after every merge: check off what closed, **correct what is now wrong**,
add what the work revealed.

## Blocked on Apple (calendar time, not work)

- [x] ~~Apple Developer Program enrolment~~ — already active, and already
      shipping two other apps to TestFlight without a Mac. Listing this as a
      blocker was an error: the setup playbook said so and it went unread.
- [ ] **Family Controls (Distribution) approved for all four bundle ids.**
      The one real long pole — a manual Apple review, and nothing in the
      existing account helps, since the other apps have no Screen Time
      surface. Request it first; the rest can be done while waiting.
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
- [ ] **Reuse the existing distribution certificate; do not mint one.** Point
      `MATCH_GIT_URL` at the repo whose `match` branch already holds it and set
      `MATCH_GIT_TOKEN` to a PAT that can read it. Apple's ceiling is about two
      and one is already spent. Run Apple account maintenance first to see the
      real count.
- [x] ~~**Live Activity.**~~ Investigated and declined — ActivityKit can only
      start one from the foreground, which is the one path Tim exists to
      avoid. It would appear only when you Timmed by opening the app.
      [ADR 002](docs/adr/002-no-live-activity.md).

## Later

- [ ] Allowance-based Modes — Screen Time can throttle rather than forbid.
- [ ] Android. `Tim/Shared/Core` would port nearly as-is; every adapter is new,
      and blocking via `AccessibilityService` is meaningfully weaker.
- [ ] 3D-printed puck with a magnet, instead of a bare sticker.

## Open bug: the Mode editor accepts no edits (blocking)

**Nothing about a Mode can be changed.** In the Simulator, tapping `Strict`
or `Run on a schedule` leaves both reading off and the schedule footer
unchanged. If this also happens on a device, the app cannot be configured at
all, so it can never block anything, and it must not ship.

Reproduced on runs 27–39. Read the whole of this before touching it: three
plausible fixes have already failed and the cost was about two hours.

**Proven**

- The editor sheet presents, and every screen renders.
- Taps reach it and its actions run: `Cancel` genuinely dismisses (assert
  that an editor-only row *disappears* — "Deep Work" is also the editor's
  navigation title, so asserting its presence proves nothing, and that
  mistake sent the first search in the wrong direction).
- `Strict` is `Toggle(isOn: $mode.isStrict)` — the simplest possible case —
  and reports `Hittable: true`, value `0` before and after a tap.
- The schedule footer never changes branch, so the model really is unchanged.
  This is independent of whatever XCUITest reports for a switch's `value`.
- The toggle *logic* is correct: `TimMode.isScheduled` is covered by seven
  Core tests that pass.

**Disproven — do not try these again**

1. *The custom `Binding(get:set:)` in `ScheduleSection`.* Replaced with a
   direct binding to `TimMode.isScheduled`. Identical failure.
2. *The editor holding its own copy in `@State`.* Bound it to `editing`
   instead via `Binding($editing)`. Worse — the sheet stopped presenting at
   all. Reverted in 0f1a79a.
3. *`familyActivityPicker` binding `$mode.selection` and clobbering the Mode
   during render.* Gave the picker its own `@State`. Identical failure. That
   change is kept because avoiding a JSON round-trip per render is worth
   having, but it fixed nothing.

**Best remaining hypothesis, untested**

The editor's body never re-renders after presentation. That fits every
observation at once — the switch never redraws, the footer never changes
branch, and `Cancel` still works because dismissing is not a re-render. It
points at sheet-within-sheet presentation (`HomeView` → `ModesView` →
`ModeEditorView`) rather than at any binding. Worth testing by presenting
the editor with a `NavigationLink` instead of a nested sheet.

**How to settle it fastest**

On a device, via TestFlight. The Simulator cannot run Screen Time, and every
Mode reachable there blocks nothing, so it was never going to answer a
question about this app's real behaviour. Ten CI runs went into an
environment that structurally could not resolve it.

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
