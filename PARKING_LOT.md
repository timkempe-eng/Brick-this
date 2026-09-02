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

## Feature gaps — what Brick users actually ask for, ranked

Research sprint, Sept 2026: App Store reviews, long-form reviews (NBC News,
Forbes, Consumer Reports, Marie Claire, Apartment Therapy, WhistleOut, The AU
Review), Brick's own FAQ and help centre, competitor teardowns (Unpluq, Opal,
Focus Phone, AppBlock, SelfBlock, BlockerHero, Sheppie), and the Apple developer
and parenting threads on how teenagers get around Screen Time. Sources at the
end of the section.

**Ranked by usefulness to someone building healthy habits — their own, and a
teenager's.** Not by cost, and not by how loudly it was asked for. Two things
moved items up: whether it prevents the failure that makes people *stop using
the product*, and whether it works when the person being restrained did not
choose the restraint. Cost is stated per item because some of the best ones are
nearly free here and some are a new entitlement.

One caveat on sourcing, since it changes how much weight these deserve: the
search index returned almost no Reddit. What follows is drawn from App Store
review text, published reviews, and competitors' feature matrices, which
over-represent people who wrote things down and under-represents the quiet
majority. Treat the ordering as a considered argument, not a measurement. The
first four are the ones worth acting on without further evidence.

### 1. Timed Un-Dad — release on a leash

- [ ] **Un-Dad for fifteen minutes, then Dad again by itself.** Every review
      describes the same failure: you release to check one thing and the phone
      stays open for an hour. Brick has no answer — "once you Unbrick your
      phone, you're back to full access". Unpluq does, and reviewers name it as
      the reason they switched.

      Top of the list because it is the everyday tool, it fixes the most common
      way a session is lost, and for a teenager it turns "can I have my phone"
      from an argument into a grant that closes itself.

      Nearly free structurally: `SessionScheduling.scheduleRelease(at:)` already
      exists and this is its mirror — a scheduled *re-*apply. `DadMode` already
      carries `autoUnDadAfter` for the other direction. Core work is a new
      session state and its tests; the adapter is a second DeviceActivity
      one-shot.

### 2. Essential apps no Mode can ever take

- [ ] **A never-block list, set once, that every Mode is intersected against.**
      The most-repeated concrete complaint in the entire corpus: a tester
      "accidentally locked themselves out of an incoming phone call from their
      family"; another "forgot to permit some infrequently used but essential
      tools like ride-sharing or banking apps and had to unbrick to edit
      settings again". Brick hard-codes exactly one exception — it refuses to
      block the Phone app — and stops there.

      Second because it does not add capability, it prevents abandonment. Being
      locked out of your bank at an airport once is enough to make someone quit
      a habit tool for good, and it is the specific fear that stops a parent
      putting this on a teenager's phone at all.

      Respects rule 3: the never-block list is a second `BlockedSelection`,
      opaque everywhere except `DadMode+FamilyControls`, which is the only place
      the subtraction can happen. Core stores and versions it; Core never looks
      inside. Pair it with a warning in the editor when a Mode's selection
      overlaps it.

### 3. Accountability release — someone else holds the key

- [ ] **A release secret held by another person.** The clearest gap between
      Brick and its competitors: AppBlock, SelfBlock, BlockerHero and Sheppie
      all ship some form of "a trusted person must approve the unlock", and
      Brick ships none. Brick's answer is physical — hide the puck — which
      reviewers do use for teenagers ("her kids can't access social media or
      games without physically reaching the device she holds onto"), but it
      falls apart the moment the child finds the Emergency Unbrick, which
      reviewers explicitly warn about.

      Third rather than first because Dad already has most of it: the tag *is*
      the key and a parent can already hold it. The actual hole is that the
      emergency allowance is a private escape hatch the phone's owner controls
      alone.

      Cheap version, and the one to build: a Mode may require a PIN to spend an
      emergency override, and the PIN is set by whoever holds the tag. Pure
      Core, no network, no new entitlement — `EmergencyAllowance.consume` grows
      a precondition. The expensive version — a real remote-approval round trip
      — needs a server and an account system, which this app deliberately does
      not have, and should stay out of scope until the cheap one proves
      insufficient.

### 4. Allowlist Modes — "only these", not "not those"

- [ ] **Invert a Mode: name the handful of apps that stay, block the rest.**
      Opal ships "blocklists and allowlists"; Brick is blocklist-only, and
      reviewers describe the consequence — a Sleep or School Mode is only ever
      as good as your memory of everything you should have listed, and every new
      app installed is a hole that opens silently.

      Fourth because it is the strongest available shape for exactly the two
      Modes that matter most for a teenager — sleep and school hours — and
      because it is the only one of these that gets *better* over time instead
      of decaying as new apps arrive.

      `FamilyActivitySelection` supports this natively, so the cost is a flag on
      `DadMode`, an editor branch, and the shield adapter reading it. Core
      treats the payload as opaque as before; only the flag is Core's business.

### 5. Say when the shield went missing

- [ ] **Record and surface every gap between what Dad thinks is blocking and
      what iOS is actually enforcing.** Reviewers found the hole directly: "if
      you go into Screen Time and tap the turn off button for brick, it
      automatically removes the restrictions". The parenting and Apple developer
      threads catalogue the rest — toggling the blocker off inside Screen Time
      settings, moving the system date, re-downloading a deleted app from the
      cloud icon.

      Fifth, and it would rank higher if Dad could *prevent* any of it. It
      cannot, and neither can Brick: on iOS a determined holder of the Screen
      Time passcode wins. What Dad can do is refuse to lie about it. Crash
      reconciliation already compares the shield against the stored session on
      every foreground; this is that comparison, kept as history and shown
      honestly, so a streak reflects what happened rather than what was
      configured. For a teenager's phone that difference is the whole product.

      Cost is small and mostly Core. Be careful what it claims: a gap is
      evidence of a gap, not proof of intent, and the copy has to say so.

### 6. A tag per Mode — the place is the Mode

- [ ] **Map each paired tag to the Mode it starts.** Sticker on the kitchen
      table starts Dinner; sticker on the desk starts Deep Work; sticker in the
      bedroom starts Sleep. Brick sells this as a hardware upsell — "one phone
      can work with multiple Bricks if you'd like to have one in your home, car,
      or work" — and at $59 a puck. Here the tags cost thirty cents, which
      makes it the cheapest real feature on this list and the one that best
      suits the DIY premise.

      `DadPersisting.pairedTagUIDs` is a flat `[String]` today, checked only for
      membership in `DadEngine`. This is `[String: UUID]` and a Mode picker at
      pairing time — genuinely a small change, and it makes choosing a Mode a
      physical act rather than a screen you have to open first.

### 7. Warn before a scheduled Mode starts

- [ ] **"Sleep Mode in ten minutes."** A schedule that lands mid-sentence gets
      resented, then disabled. The wind-down warning is standard across the
      category and is the one piece here with actual evidence behind it: limiting
      evening screen use for a week had teenagers falling asleep about twenty
      minutes earlier.

      Costs a notification and a second DeviceActivity window offset before the
      real one — the window arithmetic already lives in Core and is tested.
      Ranked below the structural items because it changes compliance, not
      capability.

### 8. Skip tonight

- [ ] **Pause a scheduled Mode for one occurrence without deleting it.**
      Unpluq lets you "pause a schedule *just for today*"; Brick makes you
      dismantle the schedule and remember to rebuild it, and reviewers report
      exactly that — schedules turned off "temporarily" and never restored.

      A one-shot suppression date on `ModeSchedule`, honoured by the window
      diff. Small, and it protects the schedules that already work from being
      thrown away for one dinner out.

### 9. Allowance Modes — throttle instead of forbid

- [ ] **Fifteen minutes of an app per day, rather than none.** *Moved here from
      "Later" — it is a researched gap, not just an idea.* Screen Time can do
      it; Brick cannot, and the all-or-nothing shape is the most common reason
      reviewers describe a Mode as too blunt to leave on.

      For a teenager it is the difference between a rule that gets negotiated
      and one that gets circumvented. Ranked ninth only because it is the
      largest build in the top half: a different Screen Time mechanism
      (`ManagedSettings` limits rather than a shield), a different notion of a
      session, and stats that count minutes rather than windows.

### 10. A weekly review worth reading

- [ ] **Per-Mode time reclaimed, time of day, best and worst days.** The one
      thing every comparison grants Opal over Brick: Brick "tracks usage but
      doesn't offer comparable analytical depth". `DadStats` and streaks already
      exist, so this is presentation over data Dad mostly has.

      Tenth because it changes motivation rather than behaviour, and because
      shared honestly it is a good conversation to have with a teenager — which
      is the version worth building. Avoid the judgemental register; a reviewer
      abandoned a competitor because it felt "annoying and intrusive and
      somewhat judgmental".

### 11. What you missed while Dadded

- [ ] **A digest, on release, of who tried to reach you.** Reviewers report the
      real cost of blocking: while bricked "users can see notifications but
      can't access them", and losing an important message is the thing that
      makes people stop trusting the tool overnight.

      Worth checking before committing: iOS may not expose enough for a
      third-party app to assemble this honestly, and a half-true digest is worse
      than none. Investigate, then decide — the honest outcome may be an ADR
      declining it, as with the Live Activity.

### 12. Modes that start when you arrive somewhere

- [ ] **Arrive at the gym, Dad starts; leave, it ends.** Focus Phone's
      differentiator and a real Brick limitation — "a standard session remains
      active until you return to the Brick", so a session can only ever end
      where it began.

      Ranked low deliberately, and against rule 7 it is the most expensive item
      here: always-on location is a new entitlement, a review surface, a battery
      cost, and a privacy story that sits badly beside a product whose current
      claim is that it never learns anything about you. The physical tag already
      solves the same problem with no entitlement at all. Do not build this
      until something the tag genuinely cannot do turns up.

### 13. The second device

- [ ] **Dadding the iPad.** Brick cannot: iPads have no NFC, and Brick's FAQ
      says so. For a household this is the obvious hole — the teenager whose
      phone is Dadded picks up the iPad — and Freedom's cross-device blocking is
      the standing comparison.

      Last because of what it costs here. A new target is a new bundle id, a
      `match` entry, an App ID, its own entitlements file, and another
      Family Controls approval waiting on Apple. It also needs shared state
      across devices, which means iCloud or a server, which the app currently
      does not have in any form. Real, valuable, and correctly the last thing on
      this list.

### Researched and deliberately not added

- **Alternative unlock frictions** — shake, tap a pattern, walk a hundred steps
  (Unpluq). The tag is already the friction, and it is a better one because it
  is somewhere else in the house. A second, weaker gate in the same app only
  gives you a way around the first.
- **AI usage analysis** (Opal). Requires the app to learn what you use, which
  rule 3 exists to prevent. Declining this is the privacy model working.
- **Desktop blocking** (Freedom). A different product.
- **Removing the internet requirement** — listed as a Brick weakness in every
  comparison ("Brick doesn't work without an internet connection"). Nothing to
  do: Dad is local-only already, Screen Time plus App Group `UserDefaults`, and
  no step of a tap touches a network. Worth saying out loud in the README,
  because it is a genuine advantage over the $59 product and nobody would guess
  it.
- **Refreshing the emergency allowance** — Brick makes you email support. Dad's
  five per rolling 30 days already restore themselves, on purpose. Already
  better; nothing to build.

### Sources

App Store reviews for *Brick — Ditch Distractions*
(`apps.apple.com/us/app/brick-ditch-distractions/id6448794069`) ·
[Brick FAQ](https://getbrick.com/pages/faq) ·
[Unpluq vs Brick](https://whatifididnt.com/blog/unpluq-vs-brick/) ·
[A year with Brick](https://whatifididnt.com/blog/brick-phone-app/) ·
[Brick alternatives](https://www.getfocusphone.com/articles/brick-alternatives/) ·
[Brick vs Opal](https://www.getfaithlock.com/resources/brick-vs-opal) ·
[NBC News two-week test](https://www.nbcnews.com/select/shopping/brick-phone-app-blocker-review-rcna259740) ·
[Marie Claire UK](https://www.marieclaire.co.uk/life/health-fitness/brick-phone-detox-device-review) ·
[The AU Review](https://www.theaureview.com/technology/brick-review/) ·
[WhistleOut](https://www.whistleout.com/CellPhones/Apps/brick-for-phone-limits-app-review) ·
[AppBlock on accountability partners](https://appblock.app/tired-of-breaking-your-own-phone-rules-try-an-accountability-partner/) ·
[How kids bypass Screen Time](https://jelliesapp.com/blog/kids-bypassing-screen-time/) ·
[Apple Developer Forums thread 773598](https://developer.apple.com/forums/thread/773598) ·
[Tech Lockdown on Screen Time gaps](https://www.techlockdown.com/articles/screen-time-not-working)

## Later

- [ ] Allowance-based Modes — *moved up into the ranked gaps above (#9)*.
- [ ] Android. `Dad/Shared/Core` would port nearly as-is; every adapter is new,
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
- The toggle *logic* is correct: `DadMode.isScheduled` is covered by seven
  Core tests that pass.

**Disproven — do not try these again**

1. *The custom `Binding(get:set:)` in `ScheduleSection`.* Replaced with a
   direct binding to `DadMode.isScheduled`. Identical failure.
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
