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

## Feature gaps — the family product, ranked

Research sprint, Sept 2026, rerun against the actual hook: **a parent teaching
healthy device habits, and a teenager who should be able to earn something for
making good decisions.** Sources at the end.

Ranked by usefulness to that pair — the parent setting the boundary and the
teenager living under it. Not by cost. The top of this list is now the most
expensive part of it, which is what happens when the hook changes: Dad is
currently a self-discipline tool that a household can share, and a family
product is a different shape.

### Two findings that should shape the design before anything is built

**Do not pay for good behaviour in screen time.** This is the strongest and
most counter-intuitive result in the corpus, and it invalidates the obvious
build. A whole category exists — ScreenCoach, Chore Champ, Carrots&Cake, EarnIt,
Zenvy — where chores and homework buy minutes. Child development researchers
find it backfires: screens become the thing "worth working for", other
activities start to feel like barriers to the reward, and cooperation turns
into negotiation — "what do I get for this?". The explicit recommendation is to
avoid tying screen access to grades, chores or daily behaviour.

Dad is not stuck with that trap, because of a distinction worth stating
plainly: **the good decision here *is* the healthy habit.** Those apps pay for
unrelated behaviour with the thing they are trying to limit. Dad rewards
choosing to Dad. So the design rule is — reward the habit, but never denominate
the reward in the thing being limited. Earned minutes are the one currency
Dad should not mint.

**Surveillance backfires too, and Dad is already built to avoid it.** Teens
whose parents used control apps experienced *more* online risk, not less, and
the apps correlate with authoritarian parenting and eroded trust. What does
work: rules the teenager helped write, transparent tools they know exist, and a
visible path to more independence. Bark and Qustodio read messages; Dad
structurally cannot, because rule 3 means the app never learns what was blocked,
let alone what was said. That is a real position in this market — *Dad is a
boundary, not a spy* — and it is worth saying out loud in the README rather than
leaving it as an implementation detail.

One caveat on evidence: a widely-repeated "40% higher compliance for
co-created rules" figure traces back to a secondary blog and I could not find
the primary study. The *direction* is well supported — adolescent involvement in
screen decisions is associated with better compliance and greater prosociality —
but do not ship that number.

### 1. A parent and a teenager are different people

- [ ] **Two roles, and the child authorization that makes them real.** Nothing
      else on this list means anything without it. Today Dad authorizes with
      Family Controls *individual* authorization: the phone's owner controls it,
      which is correct for an adult and useless for a teenager, who can revoke
      it in Settings.

      Apple provides the other path. `AuthorizationCenter.requestAuthorization(for: .child)`
      grants genuine parental control — but only on a device signed into a
      child's iCloud account inside an iCloud Family, and not MDM-enrolled. That
      constraint is the whole product decision: it is Apple's blessed route, the
      teenager cannot undo it alone, and it forces the household onto Family
      Sharing.

      First because it is a prerequisite, not a feature, and because it also
      subsumes most of the tamper problem that ranked 5th under the old framing.
      Verify the entitlement story before committing — same Family Controls
      entitlement, but a materially different request to Apple, and the
      Distribution approval is already the long pole.

### 2. Earned autonomy — the incentive, done the way the evidence supports

- [ ] **A visible ladder where consistency buys freedom, never minutes.** The
      teenager can see every rung, what it costs, and what it unlocks: set your
      own Sleep window inside a range the parent picked; edit your own Modes;
      more emergency overrides; eventually the tag lives in your room and the
      parent stops holding it.

      Second, and it is the heart of the hook. This is what "incentivize good
      decisions" should mean here — the reward is self-determination, which is
      the thing the research says teenagers actually respond to and the thing a
      parent is trying to hand over anyway. It also gives the product an ending:
      a teenager who tops the ladder is running Dad the way an adult does, which
      is the goal.

      Two design constraints that decide whether it works. The ladder must
      **ratchet slowly and never silently drop a rung** — losing a level over one
      bad night is exactly what makes a teenager stop caring. And every rung
      must be legible in advance; a reward you cannot predict is not an
      incentive. Core work is real but ordinary: a level, its rules, and the
      arithmetic from history, all testable without a Mac.

### 3. The rules get written by both people

- [ ] **A setup flow that is a negotiation, not a configuration screen.** Both
      people present, each Mode proposed and agreed, the reasoning recorded next
      to it, and a scheduled point where it gets renegotiated as trust grows.

      Third because it is cheap — it is mostly copy, flow and a stored rationale
      string — and because it is the single best-supported intervention in the
      literature. It also changes what the app *is* from the teenager's side: a
      deal they are party to rather than a restriction that appeared on their
      phone.

### 4. The teenager sees exactly what the parent sees

- [ ] **One dashboard, no hidden view.** Same streaks, same history, same
      ladder position, same record of every override. In a 2020 trial of an app
      that showed the child the identical dashboard the parent saw, most
      parent-child pairs rated it more useful and less corrosive of trust than a
      stricter tool.

      Fourth because it is nearly free — Dad has no separate parent data to hide
      — and because committing to it now stops a monitoring surface being added
      later by accident. Write it down as a rule, the way rule 3 is written down.

### 5. Request and grant

- [ ] **The teenager asks for a release; the parent grants a bounded one.**
      Apple's own "ask for more time" is the proven pattern and parents report it
      as unreliable, which is the opening. The grant must be bounded by
      construction — fifteen minutes, then it re-Dads — so that saying yes is
      not the same as giving up for the evening.

      Fifth because it is the everyday interaction of a family product, and
      because it converts the most common household argument into a two-tap
      exchange with a defined end. Depends on #6 for its mechanism.

### 6. Timed Un-Dad — release on a leash

- [ ] **Un-Dad for fifteen minutes, then Dad again by itself.** Ranked first
      under the old framing and still here on its own merits: every review
      describes releasing to check one thing and losing an hour, and Brick has no
      answer — "once you Unbrick your phone, you're back to full access".

      Now it is also the primitive under #5, which raises its value: the parent's
      grant and the teenager's own timed release are the same mechanism. Nearly
      free structurally — `SessionScheduling.scheduleRelease(at:)` exists and
      this is its mirror, a scheduled re-apply.

### 7. Essential apps no Mode can ever take

- [ ] **A never-block list every Mode is intersected against.** The
      most-repeated complaint in the review corpus — a tester "accidentally
      locked themselves out of an incoming phone call from their family";
      another forgot to permit banking and ride-sharing and had to unbrick to
      fix it. Brick hard-codes one exception, the Phone app, and stops.

      Seventh rather than second because the family framing changes who it
      protects: this is now the thing that lets a parent say yes to putting Dad
      on a teenager's phone at all, and the thing that stops a blocked maps app
      becoming a safety argument. Respects rule 3 — the list is a second opaque
      `BlockedSelection`, subtracted only inside `DadMode+FamilyControls`.

### 8. Allowlist Modes — "only these", not "not those"

- [ ] **Invert a Mode: name the few apps that stay.** Opal ships allowlists;
      Brick is blocklist-only, so a Sleep or School Mode is only as good as your
      memory, and every newly installed app is a silent hole. The strongest
      available shape for exactly the two Modes a household cares most about,
      and the only item here that improves with time instead of decaying.
      `FamilyActivitySelection` supports it natively.

### 9. Rewards the parent defines, paid in anything but minutes

- [ ] **A small ledger: the teenager earns, the parent settles up.** Pocket
      money, a lift somewhere, a later weekend curfew, choosing dinner. The app
      tracks what was earned and what was redeemed; it does not try to be a
      payments product.

      Ninth, deliberately below earned autonomy, and constrained by the finding
      above: the rewards are real-world, never screen time. Worth building
      because #2 alone is abstract for a younger teenager and a concrete reward
      bridges to it — but if only one of the two ships, ship #2.

### 10. The parent Dads too

- [ ] **Shared streaks and household goals, with the parent's own phone in
      them.** A parent's own device habits are among the strongest predictors of
      their child's, and the fastest way to make Dad feel like a punishment is
      for it to run on exactly one phone in the house.

      Tenth because it is motivational rather than structural, but it is cheap —
      Dad already has streaks and a shared physical tag — and it changes the
      product's tone more than its cost suggests.

### 11. A weekly review both people read

- [ ] **Per-Mode time reclaimed, time of day, best and worst days.** The one
      thing every comparison grants Opal over Brick: Brick "tracks usage but
      doesn't offer comparable analytical depth". `DadStats` exists, so this is
      mostly presentation.

      Aim it at a conversation, not a report card, and keep it out of the
      judgemental register — a reviewer abandoned a competitor for feeling
      "annoying and intrusive and somewhat judgmental", which is precisely how a
      teenager stops reading something.

### 12–15. Mechanics, unchanged in value and now cheaper to justify

- [ ] **A tag per Mode.** `pairedTagUIDs` is a flat `[String]` today; make it
      `[String: UUID]`. Kitchen tag starts Dinner, desk tag starts Deep Work.
      Brick charges $59 a puck for this; here the stickers are thirty cents,
      which makes it the best value on the list.
- [ ] **Warn before a scheduled Mode starts.** "Sleep Mode in ten minutes." A
      schedule that lands mid-sentence gets resented, then disabled. The one item
      with direct evidence behind it: a week of limited evening screen use had
      teenagers falling asleep about twenty minutes earlier.
- [ ] **Skip tonight.** Pause one occurrence without dismantling the schedule.
      Unpluq has it; Brick makes you delete and rebuild, so schedules get turned
      off "temporarily" and never restored.
- [ ] **Allowance Modes — throttle instead of forbid.** *Was in "Later".* Fifteen
      minutes of an app a day rather than none. For a teenager it is the
      difference between a rule that gets negotiated and one that gets
      circumvented. Largest build in this group: a different Screen Time
      mechanism entirely.

### 16–18. Real, and correctly last

- [ ] **Say when the shield went missing.** Largely subsumed by #1, which is why
      it fell from 5th. Still needed as the honest fallback for households that
      cannot use child authorization, and the copy must not overclaim: a gap is
      evidence of a gap, not proof of intent.
- [ ] **What you missed while Dadded.** Reviewers report losing important
      messages. Check feasibility first — iOS may not expose enough to build this
      honestly, and a half-true digest is worse than none. The honest outcome may
      be an ADR declining it, as with the Live Activity.
- [ ] **The second device.** The teenager whose phone is Dadded picks up the
      iPad, and Brick cannot help — iPads have no NFC. Last because of cost: a
      new bundle id, a `match` entry, another Family Controls approval, and
      cross-device state the app has no mechanism for.

### The architectural fork this creates

Two roles need shared state, and Dad currently has none — no accounts, no
network, no step of a tap that touches the internet. That property is a genuine
advantage over Brick, which every comparison notes "doesn't work without an
internet connection". Do not spend it casually.

**Start in-person, tag-mediated.** The parent already holds the tag; a grant can
be a tag tap plus a PIN entered on the teenager's phone. Zero infrastructure, no
accounts, privacy model intact, and it works on a plane. **Then CloudKit, only
when remote grant proves necessary** — iCloud Family Sharing is already a
prerequisite of #1, so CloudKit is the Apple-native answer and still needs no
server of ours. Both beat inventing a backend.

- [ ] **Reposition the README and roadmap around the family hook.** They
      currently pitch a DIY Brick for one adult. If family and teens is the hook,
      the pitch, the naming rationale and `docs/roadmap.md` all describe a
      different product than the one being built. Cheap, and it should happen
      before the feature work so the features get designed for the right user.

### Researched and deliberately not added

- **Screen time as chore currency** (ScreenCoach, Chore Champ, Carrots&Cake,
  EarnIt, Zenvy). The single biggest thing in this market and the research says
  it backfires. Declining it is the product's opinion, and #2 and #9 are the
  same intent built the way the evidence supports.
- **Message and content monitoring** (Bark, Qustodio). Rule 3 forbids it and the
  research says it damages the thing it is meant to protect. This is the privacy
  model working, not a gap.
- **Location tracking of the child.** Same reasoning. Every family app ships it;
  it is surveillance, reviewers report it as unreliable anyway, and it needs an
  always-on entitlement against rule 7. The tag solves the same problems with no
  entitlement at all.
- **Alternative unlock frictions** — shake, pattern, walk (Unpluq). The tag is a
  better friction because it is somewhere else in the house; a second, weaker
  gate only routes around the first.
- **AI usage analysis** (Opal). Requires learning what the user does, which rule
  3 exists to prevent.
- **Refreshing the emergency allowance.** Brick makes you email support; Dad's
  five per rolling 30 days already restore themselves. Already better.

### Sources

[Brick FAQ](https://getbrick.com/pages/faq) ·
App Store reviews for *Brick — Ditch Distractions* ·
[Unpluq vs Brick](https://whatifididnt.com/blog/unpluq-vs-brick/) ·
[A year with Brick](https://whatifididnt.com/blog/brick-phone-app/) ·
[Brick alternatives](https://www.getfocusphone.com/articles/brick-alternatives/) ·
[NBC News two-week test](https://www.nbcnews.com/select/shopping/brick-phone-app-blocker-review-rcna259740) ·
[Apple: AuthorizationCenter](https://developer.apple.com/documentation/familycontrols/authorizationcenter) ·
[Apple: requestAuthorization(for:)](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:)) ·
[WWDC22: What's new in Screen Time API](https://developer.apple.com/videos/play/wwdc2022/110336/) ·
[Apple: respond to a Screen Time request](https://support.apple.com/guide/iphone/respond-to-a-screen-time-request-iph74e434e84/ios) ·
[UCF: parental-control apps may be counterproductive](https://www.ucf.edu/news/apps-keep-children-safe-online-may-counterproductive/) ·
[Beyond parental control (arXiv 2503.22995)](https://arxiv.org/html/2503.22995) ·
[MIT Tech Review: child-monitoring apps need a reboot](https://www.technologyreview.com/2026/08/19/1141623/child-monitoring-apps-need-reboot/) ·
[AAP: monitoring vs independence by age](https://www.aap.org/en/patient-care/media-and-children/center-of-excellence-on-social-media-and-youth-mental-health/qa-portal/qa-portal-library/qa-portal-library-questions/balancing-online-safety-and-independence-parental-monitoring-by-age/) ·
[Psychology Today: when we use screens to reward kids](https://www.psychologytoday.com/us/blog/the-art-of-talking-with-children/202407/when-we-use-screens-to-reward-kids-they-use-screens) ·
[Why screen time as a reward can backfire](https://kesq.com/stacker-parenting-family/2026/08/04/does-screen-time-affect-behavior-why-using-it-as-a-reward-can-backfire/) ·
[Adolescent involvement in screen decisions (PMC11016903)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11016903/) ·
[Children and Screens: all in the family](https://www.childrenandscreens.org/learn-explore/research/all-in-the-family/) ·
[OurPact review](https://timily.app/guides/ourpact-review/) ·
[Earn-screen-time app roundup](https://timily.app/guides/earn-screen-time-app/)

## Later

- [ ] Allowance-based Modes — *moved up into the ranked gaps above*.
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
