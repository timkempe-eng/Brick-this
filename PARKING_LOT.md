# Parking lot

Swept after every merge: check off what closed, **correct what is now wrong**,
add what the work revealed.

## Where this stands

The ranked feature backlog below **is** the plan: eighteen gaps from a research
sprint against Brick's reviews and the child-development literature, merged in
from `claude/brick-feature-gap-research-ojpswc` along with the README that
re-pitches Dad around a household rather than one adult. That branch is now part
of this history; its CI was only ever red because it was cut from a stale `main`.

Checked boxes below are built, tested and green — not planned.

**All eighteen are now built or deliberately declined.** Sixteen are built;
#17 and #18 are declined in ADRs with the triggers that would reopen them.
The one thing still outstanding is not code: #1's authorization half needs
Apple's approval and an iCloud Family, and no amount of work here supplies
either.

The two findings above the list shaped everything: no rung anywhere pays in
screen time, and nothing added can observe anybody. Both survived contact with
sixteen features — `RewardLedger` has no multiply and no `TimeInterval` so
paying in minutes does not compile, and `ShieldGap` withholds its sentences
from a household of one so the app never reads as an audit.

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

- [~] **Two roles, and the child authorization that makes them real.** The
      roles are **built**: `HouseholdRole`, capabilities derived rather than
      stored, and enforcement in `DadEngine` rather than in a view — hiding a
      control is a lock on the door of a room with no walls, since an App
      Intent reaches the same engine. What is *not* built is the
      authorization half, which is what makes the arrangement binding rather
      than co-operative. Everything below works today between two people who
      both want it to. Nothing
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

- [x] ~~**A visible ladder where consistency buys freedom, never minutes.**~~
      **Built**, and the two constraints held: it ratchets from monotone
      quantities so no passing time can lower it, and a lapse *withholds* a
      rung with three days' warning rather than dropping one silently. Every
      rung is on screen from the first day with what it costs, because a
      reward you cannot predict is not an incentive. No rung pays in minutes;
      a test sweeps the copy for it. The
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

### 3. The rules get written by both people — built

- [x] ~~**A setup flow that is a negotiation, not a configuration screen.**~~
      **Built.** `ModeAgreement` records why a Mode exists, who agreed it, and
      when it comes up again; `AgreementsBoardView` shows every Mode and its
      standing; `AgreementView` is where the reason gets written, in free text,
      because a picked-from-a-list justification is not writing and the
      evidence is about having written something.

      The decision that makes the record worth anything: **`agreedBy` is
      derived, never passed.** The app cannot be told two people agreed
      something — it can only observe that a grown-up was here, which is a tap
      of the tag they hold. A parameter would let a screen assert "agreed
      together" about a conversation that never happened.

      The tap is offered rather than demanded, and saving without it records
      "set by one person" — which is true, and is the whole reason the
      distinction exists. A screen that refused to save would turn a record
      into a gate. Rewriting a reason keeps the history of having talked about
      it, and talking without changing anything is recorded too: a log that
      only remembers the times somebody won is not a log of a household.

### 4. The teenager sees exactly what the parent sees

- [x] ~~**One dashboard, no hidden view.**~~ **Built by construction**, which
      is the only way it stays true: there is no parent view and no child
      view anywhere in the app, and `HouseholdView` shows both people the same
      ladder. Written down here and in the code so a later screen cannot
      quietly become a monitoring surface. Same streaks, same history, same
      ladder position, same record of every override. In a 2020 trial of an app
      that showed the child the identical dashboard the parent saw, most
      parent-child pairs rated it more useful and less corrosive of trust than a
      stricter tool.

      Fourth because it is nearly free — Dad has no separate parent data to hide
      — and because committing to it now stops a monitoring surface being added
      later by accident. Write it down as a rule, the way rule 3 is written down.

### 5. Request and grant

- [x] ~~**The teenager asks for a release; the parent grants a bounded one.**~~
      **Built.** The grown-up answers by tapping their own tag — no account,
      no server, no PIN, and it works on a plane. Bounded by construction: an
      unbounded grant is unrepresentable, and the test asserts on the
      *scheduler* rather than the stored value, because a stored hour and a
      registered fifteen minutes look identical until the phone comes back
      early. An unanswered ask expires on its own rather than being granted by
      accident the next morning.
      Apple's own "ask for more time" is the proven pattern and parents report it
      as unreliable, which is the opening. The grant must be bounded by
      construction — fifteen minutes, then it re-Dads — so that saying yes is
      not the same as giving up for the evening.

      Fifth because it is the everyday interaction of a family product, and
      because it converts the most common household argument into a two-tap
      exchange with a defined end. Depends on #6 for its mechanism.

### 6. Timed Un-Dad — release on a leash

- [x] ~~**Un-Dad for fifteen minutes, then Dad again by itself.**~~ **Built**,
      opt-in per Mode, so it changes nothing until you turn it on. A second tap
      calls the break off — the outcome the tag is the only route to. An
      emergency override never starts one: that would trap someone who could
      not reach the tag, which is the situation the override exists for. Ranked
      first
      under the old framing and still here on its own merits: every review
      describes releasing to check one thing and losing an hour, and Brick has no
      answer — "once you Unbrick your phone, you're back to full access".

      Now it is also the primitive under #5, which raises its value: the parent's
      grant and the teenager's own timed release are the same mechanism. Nearly
      free structurally — `SessionScheduling.scheduleRelease(at:)` exists and
      this is its mirror, a scheduled re-apply.

### 7. Essential apps no Mode can ever take

- [x] ~~**A never-block list every Mode is intersected against.**~~ **Built**,
      as one list in Settings rather than one per Mode — the failure being
      prevented is forgetting, and a net you have to remember to fit is not one.
      Categories are excepted rather than dropped, because `.specific(categories,
      except: apps)` is native and "Social except WhatsApp" beats not shielding
      Social. The
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

- [x] ~~**Invert a Mode: name the few apps that stay.**~~ **Built**, and cheap
      because ManagedSettings already expresses it: `.all(except:)`. Both
      lists are kept, so flipping to look at the other shape is not
      destructive. An allowlist Mode refuses to ration — a usage event counts
      a *named* set and there is no "everything except" form of one. Opal
      ships allowlists;
      Brick is blocklist-only, so a Sleep or School Mode is only as good as your
      memory, and every newly installed app is a silent hole. The strongest
      available shape for exactly the two Modes a household cares most about,
      and the only item here that improves with time instead of decaying.
      `FamilyActivitySelection` supports it natively.

### 9. Rewards the parent defines, paid in anything but minutes

- [x] ~~**A small ledger: the teenager earns, the parent settles up.**~~
      **Built**, priced in days and structurally incapable of paying in
      minutes: `RewardLedger.Days` has `+`, a saturating `-` and `<`, and that
      is the complete set — no multiply, no `Double`, no duration member — and
      a test reads the file's own source to keep it so. A grown-up who means
      five pounds writes it in the reward's *name*, which Dad never parses.

      Three of the five acts need a grown-up demonstrably in the room, and the
      proof is a tap of the tag they already hold. Claiming is not one of them:
      the balance is the permission and it was earned. Settling is the
      irreversible one, so it is the one that most needs the person who did it
      to be present.

      The days come from the session history on every read. No stored balance,
      because a stored balance is a number somebody could edit and this one
      decides what a young person is owed. It counts the same days the ladder
      does — `daysEndedByAPerson` lives in one place now, after the two
      ledgers were found to have written the rule out separately and drifted.

      Originally worded: Pocket
      money, a lift somewhere, a later weekend curfew, choosing dinner. The app
      tracks what was earned and what was redeemed; it does not try to be a
      payments product.

      Ninth, deliberately below earned autonomy, and constrained by the finding
      above: the rewards are real-world, never screen time. Worth building
      because #2 alone is abstract for a younger teenager and a concrete reward
      bridges to it — but if only one of the two ships, ship #2.

### 10. The parent Dads too

- [x] ~~**Shared streaks and household goals, with the parent's own phone in
      them.**~~ **Built**, and the interesting part was where the shared state
      could live. Dad has no accounts, no server and no step of a tap that
      touches the internet — the property every comparison with Brick notices,
      and one the fork below says not to spend casually. So the **tag is the
      courier**: every tap made inside the app reads the ledger off it, merges,
      and writes it back.

      The streak counts the days *everyone* took part, so the grown-up's phone
      can end it. That is the point rather than a side effect.

      Three constraints shaped `HouseholdLedger`. Anyone who taps the tag can
      read it, so it carries an opaque id, a date and a count — a test asserts
      the encoded payload is drawn from `[0-9a-f,;d]`, which makes carrying a
      name structurally impossible however the type changes. The tag is small,
      so it is a compact line and drops the stalest member rather than failing
      to write. And it only syncs on an in-app tap, because a Shortcuts tap has
      no UI — so the number carries `asOf` and `isCurrent`, and a stale number
      is never shown as a live one.

      Household goals were **not** built. The streak is the goal; a second
      number to sync, with no evidence it helps, is a thing to keep out.

### 11. A weekly review both people read

- [x] ~~**Per-Mode time reclaimed, time of day, best and worst days.**~~
      **Built** as `WeeklyReview`, and busiest/quietest rather than best/worst.
      It refuses to report a percentage against a near-zero baseline, and says
      when there is not enough of a week to say anything — an honest empty
      state beats a chart of one bar and a bold claim. The one
      thing every comparison grants Opal over Brick: Brick "tracks usage but
      doesn't offer comparable analytical depth". `DadStats` exists, so this is
      mostly presentation.

      Aim it at a conversation, not a report card, and keep it out of the
      judgemental register — a reviewer abandoned a competitor for feeling
      "annoying and intrusive and somewhat judgmental", which is precisely how a
      teenager stops reading something.

### 12–15. Mechanics, unchanged in value and now cheaper to justify

- [x] ~~**Ten minutes' notice before a scheduled Mode lands.**~~ **Built**,
      both halves. The decision has been tested since `ScheduleWarning` landed;
      the delivery — `Notifying`, the seventh port, over UserNotifications —
      is new. Permission is asked for lazily, at the first warning there is
      something to say, rather than beside the Screen Time prompt where it
      would spend a "not now" on a feature nobody has met.

      The port takes one call rather than a schedule and a cancel, because the
      two must not be able to disagree: a cancel that fails leaves a
      notification for a night that was skipped. Exactly one warning is ever
      pending. It names the Mode, the time and how long you have, and it asks
      for nothing — a warning with a "postpone" button is a schedule you did
      not agree to. No sound: a product whose argument is that phones interrupt
      too much should not add a chime to make the point.

- [x] ~~**A tag per Mode.**~~ **Built**, and it is the first time the schema
      ladder has actually moved a shape — the envelope went in before anything
      shipped on exactly this bet. A tag naming a deleted Mode falls back to
      toggling rather than going dead, because a sticker on the fridge that
      silently does nothing is the failure this codebase hates most. It was
      `pairedTagUIDs`, a flat `[String]`; now it is
      `[String: UUID]`. Kitchen tag starts Dinner, desk tag starts Deep Work.
      Brick charges $59 a puck for this; here the stickers are thirty cents,
      which makes it the best value on the list.
- [~] **Warn before a scheduled Mode starts.** The *decision* is built —
      whether a warning is owed and the instant it should fire, including the
      cases where it must not (a session already running, a night skipped).
      The notification itself is an adapter and a port that do not exist yet.
      "Sleep Mode in ten minutes." A
      schedule that lands mid-sentence gets resented, then disabled. The one item
      with direct evidence behind it: a week of limited evening screen use had
      teenagers falling asleep about twenty minutes earlier.
- [x] ~~**Skip tonight.**~~ **Built**, and deliberately cheaper than changing
      the schedule — that is the difference between asking for tonight and
      renegotiating the rule. Checked at the boundary rather than by
      unregistering the window, because tearing down a repeating window for
      one night is the open-window failure this codebase avoids. Pauses one
      occurrence without dismantling the schedule.
      Unpluq has it; Brick makes you delete and rebuild, so schedules get turned
      off "temporarily" and never restored.
- [x] ~~**Allowance Modes — throttle instead of forbid.**~~ **Built**, and it
      was the largest job here as predicted: a different Screen Time mechanism
      entirely, behind a sixth port. "A day" means a day — a spent allowance
      carries across sessions, or ending and re-tapping would be a two-tap
      reset. *Was in "Later".* Fifteen
      minutes of an app a day rather than none. For a teenager it is the
      difference between a rule that gets negotiated and one that gets
      circumvented. Largest build in this group: a different Screen Time
      mechanism entirely.

### 16–18. Real, and correctly last

- [x] ~~**Say when the shield went missing.**~~ **Built**, and the copy does
      not overclaim: every interval is an upper bound rather than a
      measurement, because the app is absent during a gap by construction —
      "Up to 2h 10m", never a confident number. The caveat ships beside it
      rather than in a help screen: *a restart, a restore, an iOS update and a
      change in Settings all look the same from here.*

      Deliberately **not** built on "reconcile had to re-apply the shield",
      which is the obvious cheap signal and is idempotent by design — a
      detector on it would fire every time the app was opened during a session
      and produce an accusation with no evidence under it.

      An adult Dadding their own phone gets silence about the past and keeps
      only the setup note, because that is about the tool and fixable in the
      next minute. A running tally of the times Dad lost sight of the shield
      would turn a boundary they chose into a self-audit they did not.
- [x] ~~**What you missed while Dadded.**~~ **Declined**, with the trigger to
      reopen it, in [ADR 005](docs/adr/005-missed-while-dadded.md). The
      feasibility check was the answer: iOS does not expose enough to build it
      honestly, and the parking lot said in advance that a half-true digest is
      worse than none.
- [x] ~~**The second device.**~~ **Declined**, with its trigger, in
      [ADR 006](docs/adr/006-the-second-device.md). The cost was already
      written down here — a new bundle id, a `match` entry, another Family
      Controls approval, and cross-device state — and #10 has since built
      exactly one mechanism for that state, deliberately the smallest one that
      works.

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

- [x] ~~**Reposition the README and roadmap around the family hook.**~~ Done
      with the merge of the research branch, which brought its own README, and
      swept again as each feature landed. The one thing to keep watching is the
      failure this item names: a doc that describes a different product from
      the one being built. Every sweep since has found at least one.

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

## Open, and worth deciding rather than drifting

- [ ] **Should an in-flight session count toward today's streak?** It does not:
      `DadStats` filters to finished sessions, documented against totals
      drifting upward as you watch them. But the streak rule is "at least one
      session *started* that day", and an in-flight session has a start. So
      somebody who Dadded an hour ago sees a streak that does not include
      today until they tap out — on the home screen, on the widget, and in the
      shared household streak.

      Both answers are defensible and the current one is not obviously wrong,
      which is exactly why it should be decided rather than left to the
      accident of a filter written for a different purpose. Whichever wins,
      the totals and the streak probably want different filters.

## Closed (this sweep)

- [x] **The backlog is clear.** All eighteen ranked gaps are built or declined
      in an ADR, and the six items still unchecked above are the ones no amount
      of work in a Linux container can close: Apple's approvals, an App Store
      Connect record, a build on the phone, and a repository setting.

- [x] **The last seven, and what each cost.** #9 rewards, #10 the household
      streak, #16 the shield-gap report, #3's negotiation flow, the delivery
      half of the ten-minute warning, and the two ADRs. Each entry above says
      what it decided and why; what they had in common is that the interesting
      work was never the feature.

      - #10 had no shared state to use, and the fork below says not to spend
        the no-network property casually. The tag became the courier.
      - #16 arrived judging correctly and unable to observe anything;
        `ShieldControlling` gained its first *read*, and the stamp it needs had
        to survive the process dying — which is the event a gap is made of.
      - #3 arrived complete and unreachable. The decision that made it worth
        anything was refusing a parameter: `agreedBy` is derived from a tag
        tap, because an app that can be *told* two people agreed is an app
        whose record means nothing.
      - The warning had been decided and tested for days and delivered never,
        which is the shape of a feature that reads as built.

- [x] **An adversarial review found nine defects in work that had passed every
      check.** 817 tests, 106 preflight checks, the vocabulary lint and a
      green macOS job all said the night's work was sound. It was not, and two
      of the nine were the kind that quietly change what a person is owed:

      - **A reward claim refunded a day and erased a lift that was given.** The
        claim list was truncated at a constant named for a different list, and
        `spent` is derived by summing it. The list is now unbounded, with the
        reason where the bound was: truncation is a memory strategy and cannot
        also be an accounting one.
      - **Talking over an overdue rule re-filed it in the past**, so the
        conversation left the rule still overdue. The picker started on
        days-remaining, which is negative once overdue. Guarded in Core, where
        more than one caller is protected.
      - **The tag's member cap could not fit the tag's byte budget**, so the
        writing phone counted six people and every reading phone counted five
        — and the dropped one is the member whose date decides whether the
        streak is current.
      - **Any text record starting with `d` was treated as a ledger**, so
        "desk" written with NFC Tools was destroyed, and a ledger sitting
        behind one was read as garbage and then overwritten.
      - **On a full household the phone dropped itself from its own tag**, then
        read the tag back and concluded it was not a member of its household.
      - **A hole in the vocabulary lint**, opened the same night: the lint
        named the forbidden symbols, so a new alias was unwatched the moment it
        was added — and its own comment claimed the lint covered it. The lint
        is now an exemption list, so adding a symbol makes it stricter rather
        than blinder.

      **What this costs is worth stating plainly: the checks are necessary and
      they are not sufficient.** Every one of these passed all of them. A
      second pair of eyes on the diff, briefed with the defect classes this
      repo actually produces, found in twenty minutes what a night of tests did
      not. Brief the review with the classes; a general "look for bugs" would
      have found none of them.

      Around forty mutations were run in total, over the new code and the old.
      Eight survived and all eight are now covered or explained in place. The
      one that mattered most was on a fix: it survived, and the first
      explanation for why was wrong — checking the arithmetic instead of
      believing it is what turned a false comment into a true one.

- [x] **A mutation reached a pushed commit, and the suite would not have caught
      it.** An adversarial review was running `scripts/mutate.sh` in the same
      working tree, and a `git add -A` landed inside the window where the
      mutation was applied. `store.redemptions` shipped capped at 3 instead of
      `grantHistoryLimit` for one commit, corrected by the next.

      Two things worth keeping. **Never `git add -A` while a mutation harness
      is live in the same tree** — `mutate.sh` restores the file itself, so the
      only unsafe thing is somebody else staging during the window; use
      explicit paths, or run the review in a worktree.

      And the reason it was silent: **nothing tests the redemption cap.** The
      mutation survived all 803 tests, which is why it looked like an ordinary
      diff. It is the same finding the constant sweep keeps producing, arrived
      at by accident — a cap borrowed from `grantHistoryLimit` for a second
      list, with the name still saying "grant".

- [x] **A constant sweep, and what it keeps finding.** Nine constants mutated;
      three survived and now have tests — an allowance ceiling, a request's
      lifetime, a bounded exchange history. All three were the emergency-
      allowance lesson again: every test spells the number symbolically, which
      is correct style and means the whole suite moves with it.

      Two mutations found something better than a missing test. A `max(0, …)`
      on the household streak could not change any output, because the only
      path reading it already zeroed a stale run — the clamp moved to
      `HouseholdStreak`'s initialiser, where a test can reach it. And
      `reconcile`'s call to sync the schedule warning was redundant, because
      the sync above it had already made the call — except on the one path
      where the sync fails, which is exactly when a stale warning would be left
      standing. **A guard no test can reach is not a guard, and a call that
      changes nothing is usually pointing at the case it should have covered.**

- [x] **The two ledgers had written the same rule out twice.** `AutonomyLadder`
      and `RewardLedger` both counted "days somebody actually did this", and
      the copies had already drifted: one filtered on `wasEndedByAPerson`, the
      other on `wasEndedByAPerson && !endedByEmergency`, where the second
      clause could not change the answer. A redundant clause in a copied rule
      is the one that survives when the original changes — and this rule
      decides what a young person is owed. One definition now, next to the
      field it reads, with `TwoLedgersAgreeTests` walking a history containing
      every kind of ending and asserting the two modules agree about it.

- [x] **Six commits of UI went to the macOS runner at once, and two tests
      failed.** Runs 127 to 132 were all cancelled for queue contention, so
      nothing had been verified since the family screens landed. Both failures
      were the same thing: the Mode editor grew a style picker and an allowance
      section, and `SwiftUI.List` is lazy, so Strict and the schedule footer
      were not merely un-hittable but absent from the accessibility tree.

      The tests were reaching for controls by where they used to be. The lesson
      is the cancelling, not the tests: batching six commits into one
      verification is how two independent regressions arrive together and each
      makes the other harder to read.

- [x] **Eleven of the eighteen ranked gaps, built by a fan-out.** Six agents
      wrote pure Core modules in isolated worktrees — roles, the ladder,
      request-and-grant, schedule skips, the weekly review, agreements, tag
      pairing — and two more wrote ADRs and an adversarial review. Every module
      arrived with its own tests and its own mutations, and every one of them
      passed its own suite.

      **And five real defects lived in the seams between them**, which is the
      lesson worth keeping from the whole exercise. Parallel work does not
      produce wrong modules; it produces modules that are right alone and
      disagree where they meet, and no module's own test suite can see that.

      - Reaching the **top of the ladder granted nothing at all**: the ladder
        ran 0…4 and the permission table capped at 3, treating 4 as unreadable
        and collapsing it to zero. The reward path was the one thing that
        broke, silently, in the direction nobody tests.
      - **Rungs promised a wider emergency allowance** and nothing read it.
        Thirty clean days, a screen saying the allowance grew, and the sixth
        press refused.
      - The **cheapest rung bought the two above it by side effect**: clearing
        a Mode's app list took its schedule down without the edit ever naming a
        schedule.
      - **The ladder counted sessions nobody attended.** Sixty-one nights of a
        Sleep schedule climbed all four rungs with nobody touching anything —
        and rung four hands over the tag.
      - **The ratchet was a property of how much history fits.** Above about
        eight sessions a day, which is exactly what a rationed Mode produces,
        the oldest clean days fell off the 500-session cap and the "high-water
        mark" dropped — instantly, and invisibly.

      Two more found by hand: a "skip tonight" button that skipped *two* nights
      when pressed twice, because the module de-duped skips and then advanced
      past them; and the weekly review reporting the **wrong allowance**,
      having been asked for a rationed Mode's minutes and having found only the
      emergency overrides on its stale base.

      Every one is fixed, tested, and has a caught mutation. The tests that
      guard them all have the same shape: walk the whole range and assert the
      two modules agree, rather than assert each against itself.


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
