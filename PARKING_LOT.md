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
- [ ] App Store Connect record for `app.dad.Dad`
- [ ] First TestFlight build installed on the iPhone

## Next up

- [ ] **Rename the default branch to `main`.** `main` is pushed; flip it in
      Settings → Branches and delete the session branch.
- [ ] **Get the first build onto the phone.** Runbook in
      [docs/PROVISIONING.md](docs/PROVISIONING.md) — six browser steps, none
      needing a Mac. Step 1 (Family Controls approval) is the only one
      measured in days, so it goes first and the rest happen while it is
      pending. This is also what settles the editor bug above: a Simulator
      cannot run Screen Time, so it was never going to.
- [ ] **Reuse the existing distribution certificate; do not mint one.** Point
      `MATCH_GIT_URL` at the repo whose `match` branch already holds it and set
      `MATCH_GIT_TOKEN` to a PAT that can read it. Apple's ceiling is about two
      and one is already spent. Run Apple account maintenance first to see the
      real count.
- [x] ~~**Live Activity.**~~ Investigated and declined — ActivityKit can only
      start one from the foreground, which is the one path Dad exists to
      avoid. It would appear only when you Dadded by opening the app.
      [ADR 002](docs/adr/002-no-live-activity.md).

## Later

- [ ] Allowance-based Modes — Screen Time can throttle rather than forbid.
- [ ] Android. `Dad/Shared/Core` would port nearly as-is; every adapter is new,
      and blocking via `AccessibilityService` is meaningfully weaker.
- [ ] 3D-printed puck with a magnet, instead of a bare sticker.

## Closed: the Mode editor was never broken

Runs 27 to 51. The editor accepted edits the whole time. `ScreenTests` tapped
`app.switches["Strict"]`, and XCUITest reports a SwiftUI `Toggle` in a `Form`
as one element spanning the whole row — so `tap()` landed on the label, and
nothing was ever flipped. Tapping at 92% across the row fixed it and the suite
went green.

Everything the failure "showed" follows from the switch never moving: the
value stayed at 0, the schedule footer never changed branch, and `Cancel`
worked throughout because a `Button` responds anywhere in its bounds. That
last one was read as proof that taps reached the editor and only its state was
broken, which sent the search into the app and kept it there.

Five app-side fixes were attempted and all five failed identically — the
custom `Binding(get:set:)`, the editor's own `@State` copy, the picker's
binding, the nested-sheet presentation, and the `familyActivityPicker`
modifier itself. Five unrelated changes with an unmoved symptom was the signal
that the app was not at fault, and it took all five to notice.

What actually cost the time was not the wrong theories. It was:

- **A diagnostic channel that hid the answer.** `xcodebuild` was piped through
  `tail -60`, so a compile error in the test target read as an assertion
  failure for four runs. Fixing the log found the real cause in one look.
- **Assertions that could not fail.** `testAModeEditorOpensAndCloses` ended by
  asserting "Deep Work" still existed after Cancel — also the editor's
  navigation title, so it passed either way. An earlier one used `containing`
  on a static text, which matches by descendants and so matches nothing.
- **Never questioning the instrument.** Every hypothesis was about the app.
  The tap itself went unexamined until five fixes had failed.

Kept from the attempts, on their own merits rather than as fixes:
`DadMode.isScheduled` and `editableSchedule` with seven Core tests, because
that logic belongs in Core and was previously reachable only from a Simulator;
and the app picker holding its own state instead of a computed bridge that
JSON round-trips on every render. Reverted: the nested-sheet-to-push change
and gating the picker behind the UI-test flag, both made purely on failed
theories.

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
      asserted the footer would promise "your phone Dads itself"; the app
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
- [x] An unrecognised deep link no longer toggles. `dad://open` would have
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
