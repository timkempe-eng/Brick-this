# Dad — the contract

Read this before non-trivial work. It is the set of rules that are easy to
break by accident and expensive to notice later.

## What this is

A household's off switch for phones: tap an NFC sticker, the apps you chose
disappear until someone taps it again. Native Swift, five targets, no Capacitor.

**The unit is the home, not one adult.** Parents and teenagers both, everyone
playing, with a teenager earning more control over their own phone as they hold
the habit. The reward for a good decision is autonomy — never more screen time,
which is a trap an entire category fell into. Dad is a boundary, not a spy: it
cannot monitor, by construction (rule 3), and that is a commitment rather than
an omission. The README carries the philosophy in full; PARKING_LOT.md ranks the
family work, all of which is now built or declined in an ADR — what is left
there needs Apple, not code.

This began as a DIY [Brick](https://getbrick.com/) and the teardown still holds
— the $59 puck is a $0.30 sticker. That is no longer the objective. It is what
makes tags in four rooms for four phones affordable at all.

The verb is **Dad**: Dad / Dads / Dadding / Dadded, and **Un-Dad** to release.

## The machines

There is no Mac and no local shell. Three places, and knowing which does what
is most of the skill:

| Machine | Can | Cannot |
|---|---|---|
| iPad, Safari | GitHub, App Store Connect, run workflows, set secrets | Any build, test or shell |
| Agent container (Linux) | Edit, `swift test`, lint, preflight, commit, push | Build iOS. Persist anything unpushed |
| GitHub runners | Compile iOS, sign, upload to TestFlight, render the puck, hold secrets | Nothing relevant |

**If an operation needs a machine, it is a workflow.** Not a script someone runs
locally — there is no locally.

## Hard rules

1. **`Dad/Shared/Core` imports Foundation and nothing else.** Ever. It is the
   only code that can be tested without a Mac, and an iOS import silently ends
   that. Preflight fails the build if one appears.
2. **The engine depends on ports, not frameworks.** `Clock`,
   `ShieldControlling`, `SessionScheduling`, `DadPersisting`,
   `WidgetRefreshing`, `UsageWatching`, `Notifying`. New platform capability →
   new port + adapter, never a framework import in Core.
   [ADR 001](docs/adr/001-ports-and-adapters.md).
3. **Only `DadMode+FamilyControls` may interpret a `BlockedSelection` payload.**
   It is an opaque blob everywhere else. That is the privacy model made
   structural: the app is not supposed to learn which apps you blocked.
4. **The verb is never lowercased.** "Dad your phone", never "dad your phone".
   `scripts/lint-vocabulary.sh` enforces it; it crept into eight call sites
   before that existed. `modeNoun` is exempt — "mode" is a common noun.
5. **Signing is fastlane `match`, never Xcode automatic signing.**
   [docs/signing.md](docs/signing.md) explains what that costs if ignored.
   Preflight fails on `-allowProvisioningUpdates` reappearing.
6. **`CODE_SIGN_ENTITLEMENTS` stays per target.** A global value forces the
   app's entitlements onto an extension whose profile doesn't authorize them.
7. **No entitlement without a shipped feature.** Each one is a capability the
   App ID must carry, a review surface, and one more thing that can break
   signing. Preflight rejects placeholders, and requires a target's
   entitlements and its linked frameworks to agree in both directions.
   The widget is the worked example: it only reads the session, so it compiles
   a narrow source set (Core plus `UserDefaultsStore`) and carries no
   family-controls entitlement — otherwise it would be a fifth bundle id
   waiting on Apple's manual approval.
8. **`main` is the trunk.** A session branch is a scratch vehicle, not a home.
   Land finished, green work on `main` before the session ends.

## Before you push

```bash
swift test                      # 824 tests, seconds
./scripts/lint-vocabulary.sh
python3 scripts/preflight.py    # 106 checks on the Xcode wiring
```

Preflight catches what fails *silently on a device* — a mismatched App Group
leaves the shield showing the wrong Mode while the app works fine. It cannot
catch a type error; the macOS job in CI does that.

Touching `hardware/` adds one more, and it needs OpenSCAD, so it is a workflow:
push and read the **Hardware** run. It renders every part and asserts the mesh
is closed — a hole slices without complaint into a part with a side missing.

## Testing posture

The engine is a state machine over time, so it is tested with fakes and an
injected clock, not with a device. When you add behaviour, add the test that
would have caught its absence — and check the suite actually bites by breaking
the code on purpose. Six mutations were used to validate the original
suite and every one was reported red — but that was checked once and then
repeated as fact. Re-running them found one had been surviving for months.
Re-run them; do not cite them.

Use `scripts/mutate.sh` rather than a hand-rolled loop. Deciding by grepping
the output for "with N failures" is wrong — XCTest prints "with 1 failure",
singular, so every mutation caught by exactly one test reads as a survivor.
That misdiagnosis was blamed on stale incremental builds three times before the
regex turned out to be the culprit. The script decides by exit code.

It tells **three** outcomes apart, and the third was a later bug in the tool
itself. A mutation can compile and then *crash* the test binary before any test
runs — a trap in a stored property's initialiser takes the whole class down
during static setup — and that prints no "Executed N tests" line either. The
old check therefore reported a mutation the suite had caught in the loudest way
possible as invalid Swift. An adversarial review discarded three verdicts
because of it, and a discarded verdict looks exactly like a covered one. The
script now compiles first and decides "did not build" on the compiler alone.

**A constant every test spells symbolically is a constant no test covers.**
Referring to `EmergencyAllowance.perWindow` rather than `5` is correct style
and means the suite moves with the value — which is exactly why changing 5 to
500 left 240 tests passing while Settings said "of 500" and the README said
five. Three of them were like that: the override allowance, its 30-day window,
and the history bound. `PromisedNumbersTests` is the one place a literal
belongs, and every number in it is written down somewhere a person reads.
Mutation testing is what found this; the README had been claiming the opposite
for months.

Sweeping the family layer's constants the same way found three more — an
allowance ceiling, a request's lifetime, a bounded exchange history. Those live
in their behavioural homes rather than in `PromisedNumbersTests`, because what
each promises is a behaviour and not a printed number. **Do the sweep after
adding constants, not instead of it**: nine were mutated and six were already
caught, so the survivors are not predictable by eye.

Two of those mutations found something better than a missing test. **A guard no
test can reach is not a guard** — a `max(0, …)` that could not change any
output, because the only path reading it already handled the case. And a call
that changed nothing when removed, because the call above it had already made
it — on every path but the one that mattered. A surviving mutation is as often
pointing at dead code, or at the case a redundant line should have covered, as
at a missing assertion.

Things the tests deliberately pin down, because they are decisions rather than
implementation details: a session counts toward the day it *started*; a streak
with nothing today but something yesterday is still current; a day you Dadded
and then spent an override on still counts toward that streak, though not
toward a rung; an exhausted override allowance leaves the phone Dadded rather
than half-released; a scheduled Mode never stomps a session you began by hand.

From the family layer, where the decision is the feature: only a session a
*person* ended earns a rung or a reward day, and both read one definition
(`daysEndedByAPerson`) rather than each writing it out; the household streak
counts days *everyone* took part, so a grown-up's phone can end it; a stale
shared number is never shown as a live one; `agreedBy` is derived from a tag
tap and can never be passed in; and a warning is owed only for a schedule the
system actually accepted.

**Guards of the seam kind are worth more than guards of the unit kind.** The
fan-out's five real defects were all modules that were right alone and
disagreed where they met, and none of their own suites could see it. The shape
that catches those: walk the whole range, or build one input containing every
case, and assert two modules agree about it — `RungPermissionAgreementTests`,
`TwoLedgersAgreeTests`, `SharedStreakTests` (which runs two whole engines and
passes strings between them).

## Where state lives

- `docs/PROVISIONING.md` — Apple state, which is invisible from a session.
  Every ✅ cites evidence and a re-runnable check.
- `PARKING_LOT.md` — the backlog. Swept after every merge.
- `docs/roadmap.md` — what is built, what isn't, and the honest limitations.

## A new target is not just a target

It is a new bundle id, which means: a `match` entry in the Fastfile, an App ID
in the portal, its own entitlements file, and a row wherever bundle ids are
listed. Preflight checks the Fastfile list against the project's targets,
because a target `match` never signs fails at export — after the build already
succeeded.
