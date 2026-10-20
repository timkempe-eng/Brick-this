# Provisioning state

Apple's state — enrolment, app records, keys, capabilities — is invisible from
inside an agent session. This file is where it's written down, so the same
question isn't re-asked every month.

**Rule: every ✅ cites evidence and an exact re-runnable check. If you can't
re-run the check, it isn't ✅.**

| Item | State | Evidence | Re-runnable check |
|---|---|---|---|
| Repo builds the iOS app | ✅ | Actions run #10 and #11 green on `app` job | push, or re-run the Test workflow |
| Core test suite | ✅ | 939 tests, green in CI (run 38850327569) | `swift test` |
| Xcode wiring consistent | ✅ | 112 checks green | `python3 scripts/preflight.py` |
| Apple Developer Program | ✅ | Active membership already ships `app.hydive.lifeguard` and `app.hydive.member` to TestFlight | developer.apple.com → Membership shows a Team ID |
| App Group + five App IDs registered | ✅ | Account holder created them 2026-09-02 | Certificates, IDs & Profiles → Identifiers lists all five and `group.app.dad.shared` |
| Approval check runs itself | — | Retired 2026-10-12 once a build reached TestFlight: past that point it would upload an unattended build every three days. It fired eleven times, 09-10 to 10-10, and see the next row for what it reported | — |
| A scheduled firing only speaks up with news | — | It stayed quiet on all eleven firings, as designed — and all eleven were wrong to. The state it matches as "pending" is equally the state of an approved account whose App IDs don't yet have the Distribution capability enabled: the log is the same, so the classifier cannot tell them apart, and it reported "still waiting on Apple" for five weeks after Apple had approved. The quiet mode is safe only while the request is genuinely pending; it is not evidence that it is | `python3 scripts/classify_signing_failure.py --self-test` |
| Family Controls (Distribution) approved | ✅ | **Approved 2026-09-02 19:29 UTC, the day it was requested.** Apple emailed the Account Holder: *"You can now use Family Controls (Distribution) entitlement … assigned to your account, and you can now configure this capability for eligible apps."* The email sat unread, and this row said ⏳ "not approved" until 2026-10-12 on the strength of build logs that could not distinguish not-approved from not-enabled | the Account Holder's inbox: from `developer@email.apple.com`, subject *You can now use Family Controls (Distribution) entitlement.* |
| Family Controls (Distribution) enabled on the four App IDs | ✅ | Enabled by the Account Holder 2026-10-12. Release run 38276497659 then compiled and linked all five targets with no entitlement error — the first run ever to — and run 38283698097 archived and exported a signed `Dad.ipa` at 17:23:41 on the profiles it minted (`match AppStore app.dad.Dad 1791821959` and siblings) | run Release; "Successfully exported and signed the ipa file" in the log |
| App Store Connect API key | ✅ | The key hydive releases with. Keys are team-wide, so the same one signs Dad | Users and Access → Integrations lists the key id |
| All seven secrets + `MATCH_GIT_URL` | ✅ | Release run 33713075001 got past signing to the Xcode build | run Release; the Fastfile names any missing one |
| Distribution certs below the cap | ✅ | **The cap is 3.** Now 3/3: `W58S72X6S2` oxfordswimclub, `YQTXHB5NT6` hydive, `53GT6F9GRZ` Dad | run Apple account maintenance; it prints the count |
| Private `match` store | ✅ | `timkempe-eng/dad-certificates`, holding certificate `53GT6F9GRZ` encrypted | run Apple account maintenance; it prints whether the store has a match branch |
| Five provisioning profiles | ✅ | Created and installed; `All required keys, certificates and provisioning profiles are installed` | run Release |
| Family Controls capability on each App ID | ✅ | Apple-maintenance run 11 and again 2026-09-03 12:03: `FAMILY_CONTROLS` listed on `app.dad.Dad`, `.ShieldConfiguration`, `.ShieldAction`, `.ActivityMonitor`, and absent from `.Widget` — which is what rule 7 wants. `NFC_TAG_READING` on the app alone. **This says the capability is on, not that distribution is approved:** Apple's API reports a single `FAMILY_CONTROLS` type and cannot tell the self-service development variant from the reviewed distribution one, so this row would read identically either way | run Apple account maintenance; the capabilities lane prints every capability per identifier |
| App Group assigned to the App IDs | ✅ | Assigned 2026-09-03; profiles regenerated and the App Groups errors are gone | Identifiers → an App ID → App Groups → Edit shows `group.app.dad.shared` selected |
| Widget signs and builds | ✅ | Release run 33713992837: the widget target is no longer among the failures — it carries no family-controls entitlement, so nothing gates it | run Release; `in target 'DadWidget'` appears in no error |
| App Store Connect record | ✅ | Created 2026-09-03 between 12:03 and 15:15, named **Dad Your Phone**. Maintenance run at 15:15: `App Store Connect record: app.dad.Dad exists (Dad Your Phone)`. Registering the App ID on developer.apple.com is a **different site and a different action** — the two are easy to conflate, and only this one makes TestFlight possible | run Apple account maintenance; the capabilities lane says outright whether it exists |
| Upload accepted by App Store Connect | ✅ | Run 38284229412: "Successfully uploaded package to App Store Connect" at 17:29:25, build 1.0 (25) processed by 17:31:27 and distributed to internal testers. The run before it, 38283698097, was rejected for a missing icon and `NDEF` in the NFC formats; both fixed and guarded by preflight | run Release; App Store Connect → TestFlight lists the build |
| TestFlight build installed | ✅ | Build 1.0 (29) on the Account Holder's iPhone, 2026-10-13; a paired tag tapped and a tag written from Settings, both reported by the user (commits 45dd8ca, 9945085) | TestFlight app on the iPhone |
| TestFlight installs, any build | ⏳ | **Broken account-wide since 2026-10-16.** Builds 1.0 (33) and (34) read `processing=VALID internal="IN_BETA_TESTING"` in maintenance run 38953049129, in the internal group with access to all builds and 2 testers, and both testers get *"The requested app is not available or doesn't exist"* on separate Apple IDs and phones — as do the team's other TestFlight apps. The IPAs of 32 and 33 share the certificate, the profiles and every Info.plist key but the build number, and 32 installed on 10-14. Membership, Program License Agreement and Free Apps Agreement all current. It began the day builds 25–32 were expired by hand. Build 1.0 (35), which TestFlight emailed as ready to test on 2026-10-18, fails with the same message (reported by the Account Holder 2026-10-20), so the outage outlived the case being opened. Apple Developer Support case **102998937115**, opened 2026-10-16: two automated receipts (10-16, 10-18), then a phone call 2026-10-20, after which Developer Support (Tayu, `devprograms@apple.com`, 17:56 UTC) **forwarded the case to App Review**, who are to contact the Account Holder; no date given. App Review can also be reached directly at developer.apple.com/contact/app-store | try Install on the newest build in TestFlight; run Apple account maintenance for the build states |
| A tap actually blocks an app | ✅ | Build 1.0 (31), 2026-10-13, reported by the Account Holder: a tap through the Work tag's NFC automation started Deep Work with Clover closed, and the apps chosen for it disappeared. The first time the shield itself, not just the session, is confirmed on a phone | on-device only: choose an app in a Mode, tap, try to open it |
| A Shortcuts automation runs as a named tag | ✅ | Build 1.0 (31), 2026-10-13, reported by the Account Holder: the Touch Grass action shows the Tag parameter, the paired tag is listed in it by name, and an NFC automation built around it started that tag's Mode with Clover closed. The first on-device run of `TagEntity`, `TagQuery` and the `tag` parameter, none of which Linux can compile | Shortcuts → an NFC automation → Touch Grass → Tag lists the paired tags; tap the tag with Clover closed |
| Beta App Review, first external build | ⏳ | Build 1.0 (31) — release run 38442247592, commit b19057a — submitted to an external group by the Account Holder 2026-10-13, then expired by hand 2026-10-16 (maintenance run 38953049129: `external="EXPIRED"`), so a later build has to be submitted afresh. Review notes point the reviewer at any NTAG sticker, and at Emergency Exit for a reviewer without one; a bank card cannot stand in for a tag (fc0a341) | App Store Connect → TestFlight → External Testing → the group shows the build's review status |

❓ means unverified, not false. ⏳ means waiting on someone else.

## The one thing between here and TestFlight

**It was never Apple.** Family Controls (Distribution) was approved on
2026-09-02, hours after the request, and Apple said so by email. That email
went unread, and for five weeks this section said the opposite — "measured
rather than assumed, three times" — on the evidence of Release runs 33771919392
(09-03), 34137630116 (09-07) and 34355063276 (09-09), each of which minted
fresh profiles and had them rejected without `com.apple.developer.family-controls`.

Those measurements were real; the conclusion drawn from them was not. A profile
lacking the entitlement is what a pending request produces, and it is *also*
what an approved account produces while the App IDs still have only the
self-service Development variant enabled. Approval assigns the capability to
the account; it does not switch it on for any identifier. The log reads the
same either way, so "the profile lacks the entitlement" never could have meant
"Apple has not approved" — that was an inference, and it was written as a
measurement. The table row that said "Not a checkbox. Apple's approval flips
it" is where it came from, and it was a guess no one had checked.

On 2026-10-12 the Account Holder enabled Family Controls (Distribution) on the
four App IDs, and the next Release run got past the entitlement check for the
first time. Behind it were three faults no earlier run had lived long enough to
reach, found one per run:

- **codesign hung on a keychain dialog** (run 38276497659, 59 minutes, timed
  out). match imported the certificate into a keychain whose password it did
  not know, so `codesign` waited for an "allow access" click on a headless
  runner. `setup_ci` in the `beta` lane fixed it.
- **Apple's upload validation rejected the build** (run 38283698097, archive
  and export green): no image in `AppIcon.appiconset`, hence no
  `CFBundleIconName`; and `NDEF` in the NFC formats. The icon was a placeholder
  — the accent colour and the word, in Inter Bold — replaced the same day by a
  real one, and preflight now fails on either fault.

Run 38284229412 uploaded build 1.0 (25), Apple processed it in two minutes, and
it went to internal testers at 17:31 UTC on 2026-10-12 — forty days after an
approval that had taken hours.

**The approval watch, retired 2026-10-12.** What follows is its history, kept
because both of its failures are this repo's characteristic one.

The watch used to be a Claude Routine and it did not work: it fired on 09-04
and 09-07, reported success both times, and dispatched no run at all, because
its sessions were given no repository and no token. Four days of "still
waiting" were four days of nobody asking. A schedule on the runner that already
holds the secrets cannot fail that way — and note which way this failed, since
it is the one this repo keeps producing: not a broken check, a check that
reported a verdict it had never earned.

**A firing is silent unless something changed.** The first version of the
schedule reported "still waiting" by failing, which is a red run every three
days that means nothing — and a red run that means nothing is one you stop
opening, so the firing that finally matters would arrive looking exactly like
the eight before it. Worse, the good outcome was the quiet one: a run that
built and uploaded would have sent no mail at all.

So the job now passes only when the log is *exactly* the pending state, and
`scripts/classify_signing_failure.py` decides. Anything else reaches you: an
unrelated failure, a bundle id approved ahead of the others — Apple grants this
per identifier and can land them days apart — or a build that ships, which
opens an issue rather than merely going green. A manual dispatch always
reports, because somebody is waiting on it.

Swallowing a failure is the expensive mistake here, so every uncertain case is
loud: a missing log, an empty log, an error naming a bundle id the project does
not entitle, a rejection worded some third way. The four identifiers are read
out of `project.yml` and the entitlement plists rather than listed in the
script — and the plists are parsed rather than grepped, because the widget's
entitlements *mention* `family-controls` in a comment saying it deliberately
carries none, and a text search reads that as the opposite of what it says.

**What is ready.** Certificate, private `match` store, all seven secrets, five
profiles regenerating cleanly, App Group assigned, the widget signing and
building, the App Store Connect record, 110 preflight checks and the test suite
green. The pipeline runs end to end as far as Apple permits, on a run that
costs ninety seconds to repeat.

**The App Store Connect record was the other one, and it is done.** It did not
exist at 12:03 and did exist at 15:15, as *Dad Your Phone*. Worth recording how
that read from inside a session: this file said ❌ on evidence three hours old,
and the honest-looking move — trusting the written state — was the wrong one.
The table is a cache of somebody else's system, so a ❌ on an Apple row means
"absent when last asked", never "absent". Re-run the check before believing it;
it costs ninety seconds.

## What the first signing runs settled (2026-09-03)

The pipeline now runs end to end as far as Apple permits. What it cost, and
what each thing turned out to be:

- **Apple's distribution certificate cap is three.** Not two. Established by
  minting the third, which the guard had been refusing to attempt.
- **A certificate can be stranded, and once was.** `match` asks Apple for the
  certificate first and encrypts it to the store last, so a missing
  `MATCH_PASSWORD` produced a real certificate whose private key existed only
  in the runner's keychain. `LTZ92335U6` was revoked to recover the slot. The
  lane now requires that password before it calls Apple at all.
- **The certificate list alone cannot tell you what is safe to revoke.** The
  `certs` lane prints the profiles referencing each certificate, and whether
  the store holds anything, because "revoke one of these two" was otherwise a
  coin flip over two other shipping apps.
- **Four bugs sat between the secrets and the build**, each hidden behind the
  one before it: Spaceship authenticated with a sliced key hash, `pip3` refused
  on the runner's PEP 668 Python, `apply_signing.py` demanded a profile for the
  test bundle, and `../` meant two different directories to `sh` and to gym.
- **The build now stops exactly where it should.** After the App Group was
  assigned and the profiles regenerated, every remaining error is
  `com.apple.developer.family-controls`, on the four targets that need it.
  Nothing else is wrong, and nothing else can be fixed from here.
- **The widget builds and signs today.** It is absent from the failures, which
  is hard rule 7 paying for itself: keeping its source set narrow means one of
  the five targets was never waiting on Apple at all.

## What is genuinely new for Dad

This account already ships two apps to TestFlight without a Mac, so most of
the pipeline is not a blocker — it is a copy. Sorted by how long it takes:

1. **Family Controls (Distribution) approval.** The long pole, and the only
   item measured in calendar time. It is a manual Apple review, requested per
   App ID, and nothing about hydive helps: those are Capacitor apps with no
   Screen Time surface. Request it early; everything else can be done while
   waiting.
2. **Five App IDs in the portal**, and the capability enabled on four of them
   once approved. `match` does not manage capabilities.
3. **A private repo for `match` to store the certificate in.** This repo is
   public — that is what makes the macOS runners free — so it cannot hold an
   encrypted signing key. Dad gets its own store rather than sharing another
   project's, so that a revoked certificate or a `match nuke` on either side
   cannot silently break the other. Costs one distribution slot; the account
   has room.
4. **Copy the five secrets into this repo.** The values exist; repository
   secrets do not cross repositories.
5. **An App Store Connect record** for `app.dad.Dad`. Minutes.

## The four bundle ids

Family Controls (Distribution) must be approved and the capability enabled for
every one, or the profile won't authorize it:

- `app.dad.Dad`
- `app.dad.Dad.ShieldConfiguration`
- `app.dad.Dad.ShieldAction`
- `app.dad.Dad.ActivityMonitor`

`app.dad.Dad.Widget` is a fifth App ID for **signing** — it needs a `match`
profile and an App ID in the portal — but deliberately **not** for Family
Controls. It only reads the session out of the App Group, so it stays off the
approval list. Preflight fails if it ever acquires that entitlement.

## Runbook: getting the first build onto the phone

Every step below is browser work on the iPad. Nothing here needs a Mac, and
nothing here needs a session. Step 1 is the only one measured in days, so do
it first and do the rest while it is pending.

### 1. Register the App IDs and the App Group — before the request

**developer.apple.com** → Certificates, Identifiers & Profiles → Identifiers.
Not App Store Connect: they are separate sites and only one of them knows what
an App ID is. App Store Connect comes later, at step 5, and wants exactly one
of these five.

The entitlement request form asks for bundle ids, and approval is granted per
id, so these have to exist first.

**Register the App Group first.** Identifiers → + → **App Groups** →
`group.app.dad.shared`. The App Groups capability on an App ID is a picker over
groups that already exist, so doing this second means five trips back. All five
targets share it, and a mismatch shows up as the shield displaying the wrong
Mode while the app looks fine.

Then five App IDs (Identifiers → + → **App IDs** → **App**):

- **Explicit, never Wildcard.** A wildcard App ID cannot carry App Groups or
  Family Controls at all, and the radio button is easy to skim past.
- **The bundle id is case-sensitive.** `app.dad.Dad`, capital D — it must match
  `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` character for character, and
  there is no rename afterwards.
- **Description takes letters, numbers and spaces only.** Apple rejects dots and
  hyphens, so "Dad Shield Configuration", not the bundle id.
- **App Groups is two clicks.** Ticking it is not enough — use Edit/Configure
  beside the row and actually select the group.

| App ID | Capabilities |
|---|---|
| `app.dad.Dad` | Family Controls, App Groups, **NFC Tag Reading** |
| `app.dad.Dad.ShieldConfiguration` | Family Controls, App Groups |
| `app.dad.Dad.ShieldAction` | Family Controls, App Groups |
| `app.dad.Dad.ActivityMonitor` | Family Controls, App Groups |
| `app.dad.Dad.Widget` | App Groups only |

**"Family Controls" is three rows now, and only one of them is ours.** Xcode 26
split the capability, so the Identifiers list shows:

| Row | Entitlement key | Tick it? |
|---|---|---|
| Family Controls (Development) | `com.apple.developer.family-controls` | **Yes** — self-service, works immediately |
| Family Controls (Distribution) | same key | **Yes, once approved — on each of the four App IDs.** Greyed until Apple approves the account; approval does not enable it anywhere. Missing this step leaves every profile without the entitlement, which reads exactly like a pending request |
| Family Controls App and Website Usage | `com.apple.developer.family-controls.app-and-website-usage` | **No** |

The third is a different, newer entitlement: reading which apps and sites were
used, on iOS 26.4+. Dad shields apps and never reads usage, so it fails hard
rule 7 — and on 26.4+ it changes the consent prompt to all-or-nothing. There is
also a live Xcode 26.4 bug where enabling all three produces a profile carrying
`…app-and-website-usage` with the base `com.apple.developer.family-controls`
key *missing*, which would break signing for every target we have.


### 2. Request Family Controls (Distribution) — the long pole

<https://developer.apple.com/contact/request/family-controls-distribution>,
signed in. **Submitted 2026-09-02.**

**The form is shorter than every write-up says it is.** As of September 2026 it
collects profile details only — no bundle id field, no app name, no free-text
box explaining the use case. Earlier guidance in this file said to name all
four bundle ids and paste a justification; that was wrong, and it was wrong
because it came from second-hand accounts of an older form rather than from
looking at the current one. Only the Account Holder can submit it.

Two consequences worth holding lightly, because neither is verified:

- **Approval is per account, not per bundle id — for this request at least.**
  Developer reports describe per-identifier approval landing days apart; the
  email this account received says the entitlement "has been assigned to your
  account" and can be configured "for eligible apps". You then enable it on
  each App ID yourself.
- **There is no case id and no status page — but there is an email.** Apple
  sends nothing on submission and emails the Account Holder on approval, from
  `developer@email.apple.com`, subject *You can now use Family Controls
  (Distribution) entitlement.* It can land in Gmail's Updates tab. This one
  arrived 2026-09-02 19:29 UTC and went unread for five weeks.

**How we will find out it landed:** that email. Then enable Family Controls
(Distribution) on each of the four App IDs, which approval does not do, and
run Release with `force_profiles: true`. A build log cannot tell "not approved"
from "approved, not enabled", so it is not the way to find out.

If Apple replies asking what the app does — a likely follow-up given how little
the form collects — this is the answer, and it leads with the thing they are
actually screening for:

> Dad is a single-user focus tool. The person installing it is the only person
> it applies to: they choose which of their own apps to hide, and they hide
> them from themselves. There is no second account, no parent or child role, no
> remote administration, and nothing to observe another person with.
>
> The release is triggered by a physical NFC sticker. Getting your apps back
> means walking to the tag and tapping it, which is the entire point — the
> friction is the feature.
>
> Everything stays on the device. There is no server, no account, no network
> call and no analytics. The app never learns which apps were selected: the
> FamilyActivitySelection is held as opaque tokens, persisted through an App
> Group, and passed straight back to ManagedSettings without being decoded.
>
> APIs used: FamilyControls for authorization and selection; ManagedSettings
> to apply and clear the shield; DeviceActivity to start and end scheduled
> sessions. Three extensions need the entitlement alongside the app —
> ShieldConfiguration draws the shield, ShieldAction handles its buttons, and
> ActivityMonitor (DeviceActivityMonitor) applies and lifts the schedule.
>
> Bundle ids: `app.dad.Dad`, `app.dad.Dad.ShieldConfiguration`,
> `app.dad.Dad.ShieldAction`, `app.dad.Dad.ActivityMonitor`. The widget target
> reads the session only and carries no Family Controls entitlement.

**Budget a month, not a week** — though this one took under a day. Apple says
days; reports range from one day for the main app to several months with no
reply at all. Nothing else in this
runbook depends on it, so it is submitted and the rest carries on.

The usual advice for the wait is to use the *development* entitlement, which
works immediately, and test on a device from Xcode. **That does not apply to
this project**, and the reason is worth writing down because the obvious
workaround is a dead end too:

| Profile | Family Controls without approval | Installs without a Mac |
|---|---|---|
| Development | yes, the development variant | **no** — OTA install is not supported for development-signed builds |
| Ad-hoc | **no** — profiles come back without the entitlement, development variant included | yes, over the air |
| App Store | no | yes, via TestFlight |

The two halves never meet: the profile that carries the entitlement cannot be
installed without a Mac, and the one that can be installed does not carry it.
So approval gates the app reaching a phone **at all**, not just shipping, and
with it every question a Simulator cannot answer.

What this does leave open: a build carrying **no** Family Controls entitlement
is not gated by any of this, and ad-hoc plus an over-the-air install needs no
Apple review whatsoever — a distribution certificate, the phone's UDID
registered, and the `.ipa` and a `manifest.plist` served over HTTPS, which
public GitHub Release assets are. That is the only route to a real device
before approval, and it costs the three Screen Time extensions, since they
exist for nothing else.

Approval is not the same as *enabled*. Afterwards, go to each App ID's
**Additional Capabilities** tab and switch on Family Controls (Distribution),
then run Release once with `force_profiles: true` — `match` judges a profile
by expiry and certificate, not by capability set, so it will happily reuse one
minted before the capability existed.

### 3. Give `match` a private repo of its own

`match` commits an **encrypted distribution certificate and private key**.
`MATCH_PASSWORD` is the only thing protecting it, so the store has to be
private. **This repo is public** — deliberately, it is what makes the macOS
runners free — so it can never be the store. The `beta` lane now requires
`MATCH_GIT_URL` and refuses outright if it names a public repo.

Sharing another project's store is the other option and it is not taken here:
one `match nuke`, or one revoked certificate, would break releases in both
projects with no obvious connection between cause and effect. Dad keeps its
own store and mints its own certificate.

1. Create an empty **private** repo — `timkempe-eng/dad-certificates` reads
   well. It needs no contents; `match` creates the branch.
2. Repository **variable** `MATCH_GIT_URL` → `https://github.com/timkempe-eng/dad-certificates`.
   (Set `MATCH_GIT_BRANCH` too, only if you want a branch other than `match`.)
3. Repository **secret** `MATCH_GIT_TOKEN` → a fine-grained PAT with
   **Contents: read and write** on that repo *only*. Write, not read: `match`
   has to store what it mints. Actions' own `GITHUB_TOKEN` is scoped to this
   repository and cannot reach another one.

   **This token is set to never expire.** That is deliberate: an expiring one
   fails months later as a git auth error that names nothing, on the day you
   are trying to ship. The trade is acceptable because the scope is one private
   repo, Contents only, and what it guards is still encrypted with
   `MATCH_PASSWORD`. It is the only long-lived credential in this project — if
   it ever needs killing, github.com → Settings → Developer settings →
   Personal access tokens → Fine-grained tokens → Revoke, then mint a
   replacement and update the secret. Nothing else changes.
4. Repository **secret** `MATCH_PASSWORD` → a fresh passphrase. Losing it means
   revoking the certificate and starting over, so put it in the password
   manager now.

Nothing is stored in, or read from, any other project's repository.

Minting spends one of Apple's distribution slots — commonly reported as three
per standard account, two for enterprise, and not documented precisely enough
to gamble on. Run the **Apple account maintenance** workflow first to see the
real count. The `beta` lane also refuses to start if the account is at the
ceiling with nothing stored to reuse.

### 4. Copy the secrets into this repository

The values already exist; repository secrets do not cross repositories.

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | Developer account → Membership, 10 characters |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations |
| `ASC_ISSUER_ID` | Same page, above the key list |
| `ASC_KEY_P8` | **base64** of `AuthKey_XXXX.p8`, not the raw file |
| `MATCH_PASSWORD` | The passphrase the stored certificates use |

`ASC_KEY_P8` must be base64: the lane rejects anything not starting `LS0t`
rather than failing twenty minutes later as an opaque signing error.

### 5. Create the App Store Connect record

**appstoreconnect.apple.com** → My Apps → new app, bundle id `app.dad.Dad`.
Minutes.

Only the app. The four extensions never get their own record — they ship
inside the app bundle. Five App IDs, one app record.

### 6. Run Release to TestFlight

Actions → *Release to TestFlight* → Run workflow. Pick the branch, set
`force_profiles: true` for the first run after enabling capabilities.

**Run it from `main`.** This used to say to run it from the session branch,
because the certificate-reuse support (`MATCH_GIT_TOKEN`) only existed there;
that work has since landed and `main` carries it. The branch it named —
`claude/dad-phone-focus-device-tbu04b` — never existed at all: the rename to
the Dad verb was applied to the sentence and not to the branch, which is
called `claude/tim-phone-focus-device-tbu04b`. Following the instruction as
written would have sent you looking for a branch that was never there.

### What the first build will and will not show

It answers the question no Simulator can: whether tapping a tag actually
hides an app.

It will also settle the open editor bug above. If Modes cannot be configured
on the device either, that bug is real and blocking. If they configure
normally, it was a Simulator artifact and the two failing UI tests should be
deleted rather than fixed.

## Recurring, and easy to be surprised by

- Distribution certificates expire annually, and profiles with them.
- Apple's minimum SDK moves. The release workflow pins
  `xcode-version: latest-stable` for this reason; an old SDK is a rejection at
  upload, after the build already succeeded.
- API keys expire. When the email lands, the useful question isn't the date —
  it's what actually stands behind that key. Audit before treating it as an
  incident.
