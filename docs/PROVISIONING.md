# Provisioning state

Apple's state — enrolment, app records, keys, capabilities — is invisible from
inside an agent session. This file is where it's written down, so the same
question isn't re-asked every month.

**Rule: every ✅ cites evidence and an exact re-runnable check. If you can't
re-run the check, it isn't ✅.**

| Item | State | Evidence | Re-runnable check |
|---|---|---|---|
| Repo builds the iOS app | ✅ | Actions run #10 and #11 green on `app` job | push, or re-run the Test workflow |
| Core test suite | ✅ | 834 tests, green in CI | `swift test` |
| Xcode wiring consistent | ✅ | 106 checks green | `python3 scripts/preflight.py` |
| Apple Developer Program | ✅ | Active membership already ships `app.hydive.lifeguard` and `app.hydive.member` to TestFlight | developer.apple.com → Membership shows a Team ID |
| App Group + five App IDs registered | ✅ | Account holder created them 2026-09-02 | Certificates, IDs & Profiles → Identifiers lists all five and `group.app.dad.shared` |
| Approval check runs itself | ✅ | Routine `trig_016wQg4yXW2Jt6D9h5ULq3fZ`, every 3 days at 15:00 UTC: runs Release with `force_profiles: true` and reports whether the family-controls errors are gone. Push and email on. Delete it once approved | claude.ai → Routines |
| Family Controls (Distribution) | ⏳ | Requested 2026-09-02. Apple issues no case id or acknowledgement | Certificates, IDs & Profiles → the four App IDs show a Family Controls row that is not development-only |
| App Store Connect API key | ✅ | The key hydive releases with. Keys are team-wide, so the same one signs Dad | Users and Access → Integrations lists the key id |
| All seven secrets + `MATCH_GIT_URL` | ✅ | Release run 33713075001 got past signing to the Xcode build | run Release; the Fastfile names any missing one |
| Distribution certs below the cap | ✅ | **The cap is 3.** Now 3/3: `W58S72X6S2` oxfordswimclub, `YQTXHB5NT6` hydive, `53GT6F9GRZ` Dad | run Apple account maintenance; it prints the count |
| Private `match` store | ✅ | `timkempe-eng/dad-certificates`, holding certificate `53GT6F9GRZ` encrypted | run Apple account maintenance; it prints whether the store has a match branch |
| Five provisioning profiles | ✅ | Created and installed; `All required keys, certificates and provisioning profiles are installed` | run Release |
| App Group assigned to the App IDs | ✅ | Assigned 2026-09-03; profiles regenerated and the App Groups errors are gone | Identifiers → an App ID → App Groups → Edit shows `group.app.dad.shared` selected |
| Widget signs and builds | ✅ | Release run 33713992837: the widget target is no longer among the failures — it carries no family-controls entitlement, so nothing gates it | run Release; `in target 'DadWidget'` appears in no error |
| App Store Connect record | ❓ | — | Connect → Apps shows `app.dad.Dad` |
| TestFlight build installed | ❓ | — | TestFlight app on the iPhone |
| A tap actually blocks an app | ❓ | — | on-device only; nothing before this proves it |

❓ means unverified, not false. ⏳ means waiting on someone else.

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
| Family Controls (Distribution) | same key | Not a checkbox. Apple's approval flips it; a greyed row is expected |
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

- **Approval scope is unknown.** Developer reports still describe per-bundle-id
  approval, with extensions approved separately and sometimes days apart. A
  profile-only form is hard to square with that. Assume nothing; the check
  below is what settles it.
- **There is no case id and no status page.** Apple sends no acknowledgement,
  so the only honest way to know is to look at the App IDs.

**How we will find out it landed:** Certificates, Identifiers & Profiles → the
four App IDs show a Family Controls row that is no longer development-only.
Failing that, a Release run that gets past export. Nothing in this repo can
poll it.

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

**Budget a month, not a week.** Apple says days; reports range from one day for
the main app to several months with no reply at all. Nothing else in this
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
