# Tim — the contract

Read this before non-trivial work. It is the set of rules that are easy to
break by accident and expensive to notice later.

## What this is

A DIY [Brick](https://getbrick.com/): tap an NFC sticker, the apps you chose
disappear until you tap it again. Native Swift, four targets, no Capacitor.

The verb is **Tim**: Tim / Tims / Timming / Timmed, and **Un-Tim** to release.

## The machines

There is no Mac and no local shell. Three places, and knowing which does what
is most of the skill:

| Machine | Can | Cannot |
|---|---|---|
| iPad, Safari | GitHub, App Store Connect, run workflows, set secrets | Any build, test or shell |
| Agent container (Linux) | Edit, `swift test`, lint, preflight, commit, push | Build iOS. Persist anything unpushed |
| GitHub runners | Compile iOS, sign, upload to TestFlight, hold secrets | Nothing relevant |

**If an operation needs a machine, it is a workflow.** Not a script someone runs
locally — there is no locally.

## Hard rules

1. **`Tim/Shared/Core` imports Foundation and nothing else.** Ever. It is the
   only code that can be tested without a Mac, and an iOS import silently ends
   that. Preflight fails the build if one appears.
2. **The engine depends on ports, not frameworks.** `Clock`,
   `ShieldControlling`, `SessionScheduling`, `TimPersisting`. New platform
   capability → new port + adapter, never a framework import in Core.
   [ADR 001](docs/adr/001-ports-and-adapters.md).
3. **Only `TimMode+FamilyControls` may interpret a `BlockedSelection` payload.**
   It is an opaque blob everywhere else. That is the privacy model made
   structural: the app is not supposed to learn which apps you blocked.
4. **The verb is never lowercased.** "Tim your phone", never "tim your phone".
   `scripts/lint-vocabulary.sh` enforces it; it crept into eight call sites
   before that existed. `modeNoun` is exempt — "mode" is a common noun.
5. **Signing is fastlane `match`, never Xcode automatic signing.**
   [docs/signing.md](docs/signing.md) explains what that costs if ignored.
   Preflight fails on `-allowProvisioningUpdates` reappearing.
6. **`CODE_SIGN_ENTITLEMENTS` stays per target.** A global value forces the
   app's entitlements onto an extension whose profile doesn't authorize them.
7. **No entitlement without a shipped feature.** Each one is a capability the
   App ID must carry, a review surface, and one more thing that can break
   signing. Preflight rejects placeholders.
8. **`main` is the trunk.** A session branch is a scratch vehicle, not a home.
   Land finished, green work on `main` before the session ends.

## Before you push

```bash
swift test                      # 98 tests, seconds
./scripts/lint-vocabulary.sh
python3 scripts/preflight.py    # 59 checks on the Xcode wiring
```

Preflight catches what fails *silently on a device* — a mismatched App Group
leaves the shield showing the wrong Mode while the app works fine. It cannot
catch a type error; the macOS job in CI does that.

## Testing posture

The engine is a state machine over time, so it is tested with fakes and an
injected clock, not with a device. When you add behaviour, add the test that
would have caught its absence — and check the suite actually bites by breaking
the code on purpose. Six mutations were used to validate the original suite;
every one turned it red.

Things the tests deliberately pin down, because they are decisions rather than
implementation details: a session counts toward the day it *started*; a streak
with nothing today but something yesterday is still current; an exhausted
override allowance leaves the phone Timmed rather than half-released; a
scheduled Mode never stomps a session you began by hand.

## Where state lives

- `docs/PROVISIONING.md` — Apple state, which is invisible from a session.
  Every ✅ cites evidence and a re-runnable check.
- `PARKING_LOT.md` — the backlog. Swept after every merge.
- `docs/roadmap.md` — what is built, what isn't, and the honest limitations.
