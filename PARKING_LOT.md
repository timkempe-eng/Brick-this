# Parking lot

Swept after every merge: check off what closed, **correct what is now wrong**,
add what the work revealed.

## Read this first: there is a second parking lot

`claude/brick-feature-gap-research-ojpswc` carries a **295-line ranked backlog
that this file does not have** — eighteen feature gaps from a research sprint
against Brick's reviews and the child-development literature, plus a README
that re-pitches Dad around a household rather than one adult. It is unmerged,
and nothing on `main` mentions it, so it is one `git log` away from being lost.

Its CI is red, and **the failure is not its own**: it was branched from an
older `main` and carries the Mode-editor UI test that has since been fixed. Its
own jobs — core, preflight — are green, and it changes no Swift at all.

Two things need deciding, and only you can decide them:

1. **Is the product one adult, or a household?** That branch says household —
   parents and teenagers, with a teenager earning autonomy rather than minutes.
   It is a different product, and it changes what gets built next. It is also
   well argued and sourced.
2. **Does that backlog replace this section, or sit beside it?** If it lands,
   most of "Next up" below becomes a subset of it.

**Rebasing it is nearly free, and I checked rather than guessed.** Onto
`main` as it stands: three commits replay with **one conflict hunk** — a single
table row in `docs/PROVISIONING.md` arguing about a preflight check count, where
the right answer is just the current number. Onto *this* branch once it lands:
the first commit conflicts in `PARKING_LOT.md` alone, one hunk, and the two
files are additive rather than competing — the ranked list drops into a section
of its own. Either way the red goes away, because the failure is the stale base
and not the content.

Until it is merged or closed, treat this file as incomplete.

## Blocked on Apple (calendar time, not work)

- [x] ~~Apple Developer Program enrolment~~ — already active, and already
      shipping two other apps to TestFlight without a Mac. Listing this as a
      blocker was an error: the setup playbook said so and it went unread.
- [ ] **Family Controls (Distribution) approved for all four bundle ids.**
      The one real long pole — a manual Apple review, and nothing in the
      existing account helps, since the other apps have no Screen Time
      surface. Requested 2026-09-02. Apple sends no acknowledgement, so a
      Release run is the only signal; a Routine runs one every three days.
- [ ] Capability enabled on each App ID — a separate step from approval, and
      `match` does not do it. After enabling, run Release once with
      `force_profiles: true` or match reuses a profile that predates it.
- [x] ~~App Store Connect API key → the three `ASC_*` secrets, `APPLE_TEAM_ID`,
      `MATCH_PASSWORD`~~ — all seven secrets are set and proven: Release run
      33713075001 got past signing to the Xcode build.
- [ ] App Store Connect record for `app.dad.Dad`
- [ ] First TestFlight build installed on the iPhone

## Next up

- [ ] **Rename the default branch to `main`.** Settings → Branches. `main`
      exists, carries everything, and is green; the default is still
      `claude/tim-phone-focus-device-tbu04b`. Nothing in a session can flip it
      — it is a repository setting, not a git operation. Delete the session
      branch afterwards.
- [ ] **Get the first build onto the phone.** Runbook in
      [docs/PROVISIONING.md](docs/PROVISIONING.md) — browser steps from an
      iPad, none needing a Mac. Everything that can be done from here is done:
      the certificate is minted and stored, five profiles exist, the App Group
      is assigned, and the build now fails on exactly one thing —
      `com.apple.developer.family-controls`, on the four targets that need it.
- [x] ~~**Reuse the existing distribution certificate; do not mint one.**~~
      Superseded by what the signing runs found. Apple's cap is **three**, not
      two, and the account had room, so Dad minted its own (`53GT6F9GRZ`) into
      its own private store rather than sharing another project's — where one
      `match nuke` would break two shipping apps with no obvious connection
      between cause and effect. The account is now 3/3, which makes this
      finished rather than pending.
- [x] ~~**Live Activity.**~~ Investigated and declined — ActivityKit can only
      start one from the foreground, which is the one path Dad exists to
      avoid. It would appear only when you Dadded by opening the app.
      [ADR 002](docs/adr/002-no-live-activity.md).

## Later

- [x] ~~Allowance-based Modes~~ — **built.** A Mode can ration instead of
      forbid: the apps stay usable for a set number of minutes a day, then go
      until midnight. See "Closed (this sweep)".
- [x] ~~Android~~ — **investigated and declined in the form everyone builds it
      in**, with the version that would actually work kept open and given a
      trigger. [ADR 004](docs/adr/004-android.md).
- [x] ~~3D-printed puck with a magnet, instead of a bare sticker~~ — **built**,
      and it takes a position on the magnet rather than fitting one by
      default. [hardware/](hardware/).

Nothing is left in *Later*. Two items were then taken off the *other* parking
lot as well — the two that stand on their own merits whichever way the
household question goes, and that make the single-phone product better today:

- [x] ~~**Essential apps no Mode can ever take** (was #7)~~ — built. A
      never-blocked list in Settings, subtracted inside
      `DadMode+FamilyControls`, which is rule 3 as a location.
- [x] ~~**Timed Un-Dad — release on a leash** (was #6)~~ — built, opt-in per
      Mode. Tapping out gives the apps back for a while, then the Mode starts
      itself again.

Everything still on that list either presupposes the household framing or
depends on child authorization, so it waits on the decision rather than on
anyone's time.

## Known limitations, carried deliberately

- **Compiled, never run.** Screen Time and NFC both no-op in the Simulator, so
  nothing before TestFlight proves a tap blocks anything.
- **An allowance has never been counted on a device.** The rationing state
  machine is tested end to end, but every one of those tests drives it through
  a fake. Whether iOS delivers `eventDidReachThreshold` for a threshold
  registered mid-day, and how promptly, is a TestFlight question. Being wrong
  about it fails safe by construction: an allowance the system won't count
  becomes a block, and a midnight wake that never arrives is corrected on the
  next foreground.
- **`DeviceActivitySchedule` pins one weekday per window.** An every-day
  schedule collapses to one window; a part-week Mode costs several against the
  system's activity cap. Rationing Modes now draw on the same cap — one
  activity each, for as long as the session runs.

## Closed (this sweep)

- [x] **Allowance Modes — throttle instead of forbid.** Tap the tag and a
      rationed Mode leaves the apps where they are, on a daily budget; when it
      runs out the shield goes up until midnight hands back the next day's.
      What the shield should be doing is one decision in Core (`ShieldPolicy`)
      rather than four, because four callers in three processes need the
      answer. A sixth port, `UsageWatching`, over DeviceActivity's usage
      thresholds — a different mechanism from the wall-clock windows, and no
      new entitlement.

      Four things it decides rather than leaves to chance, each pinned by a
      test: strict still holds through the free period, because that is
      precisely when someone reaches for the delete-the-app hatch; an allowance
      the system refuses to count becomes a block, because one nobody counts is
      unlimited; the day boundary is derived from the stored instant rather
      than from being told, so a lost midnight wake is corrected on the next
      foreground; and editing a live Mode's allowance restarts today's count
      while editing anything else about it does not — otherwise Save would be a
      way to buy fifteen more minutes.

      47 tests, 192 total. Ten mutations run against the new code, all caught.

- [x] **The puck.** Two printed parts, no supports, about a dollar. The sticker
      lives sealed inside the lid with 1.8mm of plastic over it. It ships with
      **no magnet by default** and says why: a neodymium disc behind a plain
      tag detunes its antenna, and the tap then fails intermittently at a
      distance that varies by phone — the worst failure available to a product
      that consists of one interaction. Steel is likewise the wrong ballast and
      the README weighs four alternatives that aren't. Rendered by a workflow
      rather than committed, and checked for holes, because a mesh that isn't
      closed slices without complaint into a part with a side missing.

- [x] **Breaks — release on a leash.** Opt-in per Mode. Every review of this
      category has the same sentence in it — you unblock to check one thing
      and lose an hour — and Brick's answer is "you're back to full access".
      Tapping out now gives the apps back for a set time and then the Mode
      starts itself again; tapping a second time calls the break off, which is
      the outcome the tag is the only route to.

      `unDad` gained a reason rather than a second boolean, because two
      questions ride on how a session ended — clean finish, and start a break
      — and they do not line up on one flag. An emergency override never
      starts a break: the override is for when the tag is out of reach, and
      coming back in fifteen minutes is exactly the trap it exists to prevent.

      25 tests, six mutations, all caught.

- [x] **A never-blocked list.** The most-repeated complaint in the review
      corpus is someone locking themselves out of something they needed — an
      incoming call from family, a banking app, ride-sharing. One list, not one
      per Mode, because the failure being prevented is forgetting. Categories
      are excepted rather than dropped, since `.specific(categories, except:
      apps)` is native and "Social except WhatsApp" beats not shielding Social.

- [x] **Android, decided.** Not deferred again. The mechanism everyone uses is
      an `AccessibilityService` the user disables in three taps — which is the
      exact failure the teardown identifies as the reason this product exists —
      and Android 17's Advanced Protection Mode is closing that API to
      non-accessibility apps anyway. The route that works, `setPackagesSuspended`
      under device-owner, is *stronger* than the iOS shield and costs a factory
      reset, which is free on exactly one day: when a phone is being set up for
      somebody else. That makes Android a dependency of the household question
      rather than a platform question. [ADR 004](docs/adr/004-android.md).

- [x] **A mutation that had been surviving for months.** Re-ran the original
      six against the enlarged suite to check the new work hadn't blunted the
      old, and one of them did not turn it red — while both CLAUDE.md and the
      README asserted that it did. Every test spells the override allowance
      `EmergencyAllowance.perWindow`, so the whole suite moves with the
      constant: change 5 to 500 and 240 tests pass while Settings says "of
      500". The 30-day window and the 500-session history bound were the same.
      `PromisedNumbersTests` pins the numbers the product actually promises,
      and CLAUDE.md now says to re-run the mutations rather than cite them —
      the claim had been checked once and repeated as fact ever since.

- [x] **Three bugs found reviewing my own work, before anyone else read it.**
      Picking a Mode from the "which Mode?" dialog during a break cancelled
      the break instead of starting the Mode, so the dialog appeared, you
      answered it, and nothing happened. A break inside a scheduled window
      returned a hand-started session, which the schedule’s own boundary
      deliberately refuses to end — Sleep would have stayed on all day. And
      "15 minutes a day" reset on every new session, so ending and re-tapping
      handed the time back, which made the label false in the most obvious way
      anyone would find. Each has a test and a caught mutation.

- [x] **Four stale facts corrected.** `docs/PROVISIONING.md` told you to run
      Release from `claude/dad-phone-focus-device-tbu04b`, a branch that has
      never existed — the rename to the Dad verb was applied to the sentence
      and not to the branch, which is `claude/tim-phone-focus-device-tbu04b`,
      and `main` carries that work now regardless. `CLAUDE.md` said four
      targets (five), listed four of the six ports, and quoted test and check
      counts two features out of date. Schema versioning was still listed as a
      known limitation after being built.

## Closed

- [x] **The verb is Dad.** Renamed throughout — code, bundle ids, App Group,
      docs — while nothing was registered with Apple, which is the only moment
      the identifiers are free to change. Done with boundary-anchored rules,
      not a blanket substitution: "tim" is a substring of time, timer,
      estimate, optimize, and of `timkempe-eng`, which appears in the release
      workflow and must not move. It reached one thing it should not have: a
      branch name, in a runbook, pointing at a branch that then did not exist.
- [x] **CI says what failed.** `xcodebuild` no longer goes through `tail`; the
      full log and the `.xcresult` are kept as artifacts and the failure is
      grepped out. This is what ended the editor hunt, and it was one commit.
- [x] **The Mode editor was never broken.** Runs 27 to 51. `ScreenTests` tapped
      `app.switches["Strict"]`, and XCUITest reports a SwiftUI `Toggle` in a
      `Form` as one element spanning the whole row — so `tap()` landed on the
      label and nothing was ever flipped. Five app-side fixes failed
      identically before the instrument itself was questioned. What cost the
      time was not the wrong theories: it was a diagnostic channel that hid the
      answer (`xcodebuild` through `tail -60`), assertions that could not fail
      (asserting a string that was also the navigation title), and never
      doubting the tap.
- [x] **The schedule toggle was never broken either.** The UI test asserted the
      footer would promise "your phone Dads itself"; the app refused, because a
      starter Mode blocks nothing and a Mode that blocks nothing is never
      registered with the scheduler. The app was right every time.
- [x] **Schema versioning.** Stored values carry the version that wrote them,
      so a future shape change migrates instead of silently resetting Modes and
      history. Data written by a *later* build is detected and reported rather
      than treated as corrupt, so a TestFlight rollback can't destroy what it
      merely fails to understand.
- [x] **Simulator launch test.** The app provably launches, renders and
      survives a relaunch — which compilation never showed.
- [x] **Mutation harness** (`scripts/mutate.sh`). The hand-rolled loop decided
      by grepping for "with N failures" and XCTest prints "with 1 failure", so
      every mutation caught by exactly one test read as a survivor. Blamed on
      stale builds three times before the regex turned out to be the cause.
- [x] **Lock Screen widget.** Status and a live timer without unlocking. What
      it says lives in Core as `WidgetSnapshot` and is tested; the extension is
      layout. A fifth port, `WidgetRefreshing`, means every process that can
      end a session clears the Lock Screen.
- [x] An unrecognised deep link no longer toggles. `dad://open` would have
      fallen through to the toggle default, so tapping the widget to *check*
      your status would have released a live session.
- [x] **Full-codebase review**: ten findings, nine fixed, one wired into the
      UI. The scheduler adapter was the cluster — cross-midnight weekday
      windows ended a week late, any edit tore down every window including open
      ones, and registration failures were recorded as success.
- [x] A schedule boundary can no longer end a session you started by hand with
      the same Mode — sessions carry a started-by-schedule marker.
- [x] A timed session now ends (or re-arms) at reconcile even if its release
      registration was lost with the process.
- [x] Engine testable at all — ports and adapters, 98 tests (was 15)
- [x] iOS layer compiles, on a GitHub macOS runner, every push
- [x] Scheduled Modes
- [x] Stats and streaks
- [x] Signing reworked to `match` after reading the hydive playbook
